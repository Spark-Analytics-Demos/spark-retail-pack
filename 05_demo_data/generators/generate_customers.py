"""
Generate customer tables across Shopify, Stripe, and Klaviyo.

Produces:
  shopify/customers.csv
  stripe/customers.csv
  klaviyo/profiles.csv
"""

import pandas as pd
import numpy as np
from faker import Faker
from datetime import datetime, timedelta, timezone


def generate_customers(rng: np.random.Generator, cfg: dict, seg_config: dict, company: dict) -> dict:
    """
    Returns dict with DataFrames: shopify_customers, stripe_customers, klaviyo_profiles.
    """
    n_customers = cfg["customer_count"]
    fake = Faker()
    Faker.seed(int(rng.integers(0, 2**31)))

    segments = seg_config["segments"]
    seg_names = [s["name"] for s in segments]
    seg_shares = [s["share"] for s in segments]

    geo_markets = company["geography"]["markets"]
    country_codes = [m["country_code"] for m in geo_markets]
    country_shares = [m["share"] for m in geo_markets]
    country_currencies = {m["country_code"]: m["currency"] for m in geo_markets}
    country_regions = {m["country_code"]: m["regions"] for m in geo_markets}

    email_sub_cfg = seg_config["email_subscription"]
    customer_states_cfg = seg_config["customer_states"]

    store_open = datetime(2022, 6, 1, tzinfo=timezone.utc)
    year_end = datetime(2026, 12, 31, tzinfo=timezone.utc)

    # Assign segments
    seg_choices = rng.choice(len(seg_names), size=n_customers, p=seg_shares)

    # Assign geographies
    country_choices = rng.choice(len(country_codes), size=n_customers, p=country_shares)

    shopify_rows = []
    stripe_rows = []
    klaviyo_rows = []

    stripe_customer_id = 1
    klaviyo_profile_id = 1

    # Pre-generate all emails to guarantee uniqueness
    used_emails = set()

    def unique_email():
        for _ in range(100):
            e = fake.email()
            if e not in used_emails:
                used_emails.add(e)
                return e
        # Fallback: guaranteed unique
        e = f"user{len(used_emails)}@northwind-demo.com"
        used_emails.add(e)
        return e

    state_names = list(customer_states_cfg.keys())
    state_weights = list(customer_states_cfg.values())

    for i in range(n_customers):
        cid = i + 1
        seg_idx = int(seg_choices[i])
        segment = segments[seg_idx]

        country_idx = int(country_choices[i])
        country_code = country_codes[country_idx]
        market = geo_markets[country_idx]
        regions = market.get("regions", [])
        if regions:
            region_weights = [r["weight"] for r in regions]
            total_w = sum(region_weights)
            region_weights = [w / total_w for w in region_weights]
            region_idx = int(rng.choice(len(regions), p=region_weights))
            province_code = regions[region_idx]["code"]
        else:
            province_code = None

        # Customer creation date: spread across store lifetime, weighted toward recent
        days_since_open = (year_end - store_open).days
        # Exponential-ish weighting toward more recent (growth trend)
        u = float(rng.beta(1.5, 1.0))
        created_ts = store_open + timedelta(days=int(u * days_since_open))

        email = unique_email()
        first_name = fake.first_name()
        last_name = fake.last_name()
        phone = fake.phone_number() if rng.random() < 0.62 else None

        accepts_marketing = rng.random() < email_sub_cfg["shopify_accepts_marketing_rate"]
        accepts_sms = rng.random() < email_sub_cfg["sms_subscribed_rate"] if accepts_marketing else False

        state = str(rng.choice(state_names, p=state_weights))
        orders_count = 0  # updated after order generation; placeholder
        total_spent = 0.0  # same

        city = fake.city()
        postal_code = fake.postcode()
        country_currency = country_currencies[country_code]

        shopify_rows.append({
            "id": cid,
            "created_at": created_ts.isoformat(),
            "updated_at": created_ts.isoformat(),
            "email": email,
            "first_name": first_name,
            "last_name": last_name,
            "phone": phone,
            "accepts_marketing": accepts_marketing,
            "accepts_sms_marketing": accepts_sms,
            "state": state,
            "default_address_country_code": country_code,
            "default_address_province_code": province_code,
            "default_address_city": city,
            "default_address_zip": postal_code,
            "default_address_company": None,
            "tags": None,
            "note": None,
            "orders_count": orders_count,
            "total_spent": total_spent,
            # Internal fields used by segment assignment
            "_segment": segment["name"],
            "_email": email,    # keep plaintext for internal cross-referencing
            "_country": country_code,
            "_province": province_code,
            "_currency": country_currency,
        })

        # Stripe customer (~70% of customers)
        if rng.random() < 0.70:
            stripe_cid = f"cus_{stripe_customer_id:012d}"
            stripe_customer_id += 1
            stripe_created_unix = int(created_ts.timestamp())
            stripe_rows.append({
                "id":          stripe_cid,
                "created":     stripe_created_unix,
                "email":       email,
                "name":        f"{first_name} {last_name}",
                "phone":       phone,
                "delinquent":  False,
                "livemode":    True,
            })

        # Klaviyo profile (~78% of customers)
        if rng.random() < email_sub_cfg["klaviyo_profile_rate"]:
            klaviyo_pid = f"KP{klaviyo_profile_id:08d}"
            klaviyo_profile_id += 1
            klaviyo_rows.append({
                "id":                       klaviyo_pid,
                "created":                  created_ts.isoformat(),
                "updated":                  created_ts.isoformat(),
                "email":                    email,
                "first_name":               first_name,
                "last_name":                last_name,
                "phone_number":             phone,
                "email_marketing__consent": "subscribed" if accepts_marketing else "unsubscribed",
                "sms_marketing__consent":   "subscribed" if accepts_sms else "unsubscribed",
                "_shopify_customer_id":     cid,
            })

    return {
        "shopify_customers": pd.DataFrame(shopify_rows),
        "stripe_customers": pd.DataFrame(stripe_rows),
        "klaviyo_profiles": pd.DataFrame(klaviyo_rows),
    }


def update_customer_order_stats(shopify_customers: pd.DataFrame, orders: pd.DataFrame) -> pd.DataFrame:
    """
    After orders are generated, update orders_count and total_spent on customers.
    """
    if orders.empty:
        return shopify_customers

    active_orders = orders[orders["financial_status"].isin(["paid", "partially_paid", "partially_refunded"])]
    order_stats = (
        active_orders
        .groupby("customer_id")
        .agg(
            orders_count=("id", "count"),
            total_spent=("total_price", "sum"),
            # last_order_at: Shopify sets customer.updated_at on every order,
            # so we mirror that to keep the 24-month activity filter honest in
            # fact_customer_state_daily's active_customers CTE.
            last_order_at=("created_at", "max"),
        )
        .reset_index()
        .rename(columns={"customer_id": "id"})
    )
    order_stats["id"] = order_stats["id"].astype(int)

    updated = shopify_customers.copy()
    updated["id"] = updated["id"].astype(int)
    updated = updated.drop(columns=["orders_count", "total_spent"])
    updated = updated.merge(order_stats, on="id", how="left")
    updated["orders_count"] = updated["orders_count"].fillna(0).astype(int)
    updated["total_spent"] = updated["total_spent"].fillna(0.0).round(2)

    # Update updated_at to the customer's most recent order date for customers
    # who have placed orders. Mirrors Shopify behaviour where updated_at advances
    # on every order, ensuring these customers pass the 24-month activity window
    # in fact_customer_state_daily.
    mask = updated["last_order_at"].notna()
    updated.loc[mask, "updated_at"] = updated.loc[mask, "last_order_at"]
    updated = updated.drop(columns=["last_order_at"])

    return updated
