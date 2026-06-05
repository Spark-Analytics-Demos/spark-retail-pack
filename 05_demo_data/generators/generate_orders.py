"""
Generate Shopify orders, order_line_items, refunds, transactions and
Stripe charges and refunds.

Seasonality multipliers per §9.8 are applied to a baseline daily rate.
Story overlays modify the stream during their active windows.
"""

import json
import math
import pandas as pd
import numpy as np
from datetime import date, datetime, timedelta, timezone

from stories import (
    story_1_black_friday as s1,
    story_2_inventory_crisis as s2,
    story_3_pricing_churn as s3,
    story_4_viral_moment as s4,
    story_5_resort_wear_flop as s5,
)

# Seasonality multipliers per §9.8
MONTHLY_MULTIPLIER = {
    1: 0.85, 2: 0.78, 3: 0.92, 4: 0.95, 5: 1.00,
    6: 1.02, 7: 0.94, 8: 0.96, 9: 1.08, 10: 1.05,
    11: 1.65, 12: 1.40,
}
DOW_MULTIPLIER = {
    0: 0.85,  # Monday
    1: 0.92,  # Tuesday
    2: 0.95,  # Wednesday
    3: 1.00,  # Thursday
    4: 1.08,  # Friday
    5: 1.18,  # Saturday
    6: 1.12,  # Sunday
}

# Default acquisition channel distribution (from customer_segments.yml)
DEFAULT_CHANNELS = [
    ("meta",           "facebook / cpc",   "facebook", "cpc",     0.38),
    ("organic_search", "google / organic", "google",   "organic", 0.22),
    ("direct",         None,               None,       None,      0.18),
    ("referral",       None,               "referral", "referral",0.12),
    ("google_ads",     "google / cpc",     "google",   "cpc",     0.10),
]
DEFAULT_CHANNEL_WEIGHTS = [c[4] for c in DEFAULT_CHANNELS]

DEVICE_TYPES = ["mobile", "tablet", "desktop"]
DEVICE_WEIGHTS = [0.52, 0.10, 0.38]
DEVICE_WIDTHS = {"mobile": 375, "tablet": 768, "desktop": 1440}

BROWSERS = ["Chrome", "Safari", "Firefox", "Edge"]
BROWSER_WEIGHTS = [0.65, 0.22, 0.08, 0.05]

PAYMENT_GATEWAYS = ["shopify_payments", "paypal", "stripe"]
GATEWAY_WEIGHTS = [0.72, 0.18, 0.10]

CARD_BRANDS   = ["visa", "mastercard", "amex", "discover"]
CARD_WEIGHTS  = [0.50,   0.30,         0.12,   0.08]
CARD_FUNDING  = ["credit", "debit", "prepaid"]
CARD_FUNDING_W= [0.65,    0.30,    0.05]
CARD_WALLETS  = [None, None, None, None, "apple_pay", "google_pay"]  # ~33% wallet
CARD_EXP_YEARS= ["2026", "2027", "2028", "2029", "2030"]

FINANCIAL_STATUSES = ["paid", "partially_refunded", "refunded", "voided"]
FIN_STATUS_WEIGHTS = [0.91, 0.04, 0.04, 0.01]


def _daily_order_count(d: date, base_daily_rate: float, rng: np.random.Generator) -> int:
    multiplier = MONTHLY_MULTIPLIER[d.month] * DOW_MULTIPLIER[d.weekday()]

    # Story 1: BFCM
    if s1.is_bfcm_date(d):
        multiplier *= s1.get_day_multiplier(d)

    # Story 4: viral moment
    if s4.is_viral_period(d):
        multiplier *= s4.get_viral_day_multiplier(d)

    # Story 3: repeat rate suppression affects returning-customer orders
    churn_factor = s3.get_repeat_rate_multiplier(d)
    # Apply ~40% of the churn suppression to overall volume (returning customers are ~40% of orders)
    multiplier *= (1.0 - 0.40 * (1.0 - churn_factor))

    mean = base_daily_rate * multiplier
    # Poisson noise
    return int(rng.poisson(mean))


def _pick_channel(d: date, rng: np.random.Generator) -> tuple:
    """Returns (channel, source_value, utm_source, utm_medium)."""
    if s1.is_bfcm_date(d):
        overrides = s1.CHANNEL_OVERRIDES
    elif s4.is_viral_period(d):
        overrides = s4.CHANNEL_OVERRIDES
    else:
        overrides = None

    if overrides:
        ch_names = list(overrides.keys())
        ch_weights = list(overrides.values())
    else:
        ch_names = [c[0] for c in DEFAULT_CHANNELS]
        ch_weights = DEFAULT_CHANNEL_WEIGHTS

    idx = int(rng.choice(len(ch_names), p=ch_weights))
    ch_name = ch_names[idx]
    # Look up source value from defaults
    for c in DEFAULT_CHANNELS:
        if c[0] == ch_name:
            return c[0], c[1], c[2], c[3]
    return ch_name, None, None, None


def _sample_order_value(segment_name: str, base_aov: float, rng: np.random.Generator,
                         aov_multiplier: float = 1.0) -> float:
    """Log-normal order value per §9.8, adjusted for segment AOV multiplier."""
    seg_aov_mult = {"one_time": 1.0, "casual_repeat": 1.0, "loyal": 1.15, "vip": 1.4}.get(segment_name, 1.0)
    mean_ln = math.log(base_aov * seg_aov_mult * aov_multiplier)
    val = rng.lognormal(mean=mean_ln, sigma=0.45)
    return max(15.0, round(val, 2))


def _build_note_attributes(utm_source, utm_medium, utm_campaign) -> str:
    attrs = []
    if utm_source:
        attrs.append({"name": "utm_source", "value": utm_source})
    if utm_medium:
        attrs.append({"name": "utm_medium", "value": utm_medium})
    if utm_campaign:
        attrs.append({"name": "utm_campaign", "value": utm_campaign})
    return json.dumps(attrs)


def _generate_line_items(
    order_id: int, net_amount: float, variants_df: pd.DataFrame,
    products_df: pd.DataFrame, order_date: date, rng: np.random.Generator,
) -> list[dict]:
    """Generate 1–5 line items summing to approximately net_amount."""
    n_lines = int(rng.choice([1, 2, 3, 4, 5], p=[0.30, 0.35, 0.20, 0.10, 0.05]))
    n_lines = min(n_lines, len(variants_df))

    # Filter out resort wear until launch; filter out viral SKU if stocked out
    mask = pd.Series([True] * len(variants_df), index=variants_df.index)
    rw_mask = variants_df["sku"].str.startswith("RW-", na=False)
    if order_date < s5.LAUNCH_DATE:
        mask &= ~rw_mask
    # Filter out stockout SKUs (IDs are now integers, matching variants_df["id"])
    if s2.is_stockout_period(order_date):
        mask &= variants_df["id"] != s2.STOCKOUT_VARIANT_ID
    if not s4.is_cargo_pants_available(order_date):
        mask &= variants_df["id"] != s4.VIRAL_VARIANT_ID

    avail = variants_df[mask]
    if avail.empty:
        avail = variants_df

    chosen = avail.sample(n=min(n_lines, len(avail)), replace=False,
                          random_state=int(rng.integers(0, 2**31)))

    lines = []
    line_id_base = order_id * 100
    for k, (_, row) in enumerate(chosen.iterrows()):
        qty = int(rng.choice([1, 2, 3], p=[0.72, 0.22, 0.06]))
        price = float(row["price"])

        # Apply sweater price multiplier from story 3
        prod_row = products_df[products_df["id"] == row["product_id"]]
        if not prod_row.empty and prod_row.iloc[0]["product_type"] == "Tops":
            if "Sweater" in str(prod_row.iloc[0].get("title", "")):
                price = round(price * s3.get_sweater_price_multiplier(order_date), 2)

        # Apply resort wear clearance discount
        if str(row["sku"]).startswith("RW-"):
            price = round(price * s5.get_resort_wear_price_multiplier(order_date), 2)

        total_discount = round(price * qty * (float(rng.uniform(0, 0.05))), 2)
        tax_rate = 0.08
        line_tax = round((price * qty - total_discount) * tax_rate, 2)

        prod_title = prod_row.iloc[0]["title"] if not prod_row.empty else "Product"
        vendor = prod_row.iloc[0]["vendor"] if not prod_row.empty else "Northwind Co."

        lines.append({
            "id": line_id_base + k,
            "order_id": order_id,
            "variant_id": int(row["id"]),
            "product_id": int(row["product_id"]),
            "sku": row["sku"],
            "title": prod_title,
            "name": f"{prod_title} - {row['title']}",
            "variant_title": row["title"],
            "quantity": qty,
            "price": price,
            "total_discount": total_discount,
            "tax_lines": json.dumps([{"title": "Tax", "rate": tax_rate, "price": line_tax}]),
            "fulfillment_status": "fulfilled",
            "requires_shipping": True,
            "taxable": True,
            "gift_card": False,
            "properties": json.dumps([]),
            "vendor": vendor,
        })
    return lines


def generate_orders(
    rng: np.random.Generator, cfg: dict, products_data: dict,
    customers_df: pd.DataFrame, seg_config: dict, company: dict
) -> dict:
    """
    Returns dict with keys: shopify_orders, shopify_order_line_items,
    shopify_refunds, shopify_transactions, stripe_charges, stripe_refunds.
    """
    n_orders_target = cfg["order_count"]
    start_date = date(2026, 1, 1)
    end_date = date(2026, 12, 31)
    total_days = (end_date - start_date).days + 1

    # Base daily rate: needs to produce n_orders_target over the year
    # Compute sum of multipliers across all days to normalize
    daily_multiplier_sum = sum(
        MONTHLY_MULTIPLIER[(start_date + timedelta(days=i)).month] *
        DOW_MULTIPLIER[(start_date + timedelta(days=i)).weekday()]
        for i in range(total_days)
    )
    base_daily_rate = n_orders_target / daily_multiplier_sum

    variants_df = products_data["product_variants"]
    products_df = products_data["products"]
    locations = company["shopify"]["locations"]
    location_id = locations[0]["id"]
    base_aov = 110.0  # ln(110), per §9.8

    # Pre-build O(1) lookup dicts for per-order customer attributes
    seg_map = dict(zip(customers_df["id"], customers_df["_segment"]))
    cust_ids = customers_df["id"].values
    cust_email = dict(zip(customers_df["id"], customers_df["_email"]))
    cust_country = dict(zip(customers_df["id"], customers_df["_country"]))
    cust_province = dict(zip(customers_df["id"], customers_df["_province"]))

    order_rows = []
    line_rows = []
    refund_rows = []
    txn_rows = []
    stripe_charge_rows = []
    stripe_refund_rows = []

    order_id = 5000001
    refund_id = 7000001
    txn_id = 8000001
    stripe_charge_id = 1

    # Track which customers have ordered (for repeat order assignment)
    ordered_customers = set()
    all_customer_ids = list(cust_ids)

    # Expected values accumulators
    ev = {"gmv": 0.0, "order_count": 0, "new_customers": 0}

    current_date = start_date
    while current_date <= end_date:
        n_today = _daily_order_count(current_date, base_daily_rate, rng)
        is_bfcm = s1.is_bfcm_date(current_date)
        is_viral = s4.is_viral_period(current_date)
        repeat_rate_mult = s3.get_repeat_rate_multiplier(current_date)

        for _ in range(n_today):
            # Pick customer: new vs returning
            base_new_rate = 0.58
            if is_bfcm:
                new_rate = s1.NEW_CUSTOMER_RATE_OVERRIDE
            elif is_viral:
                new_rate = 0.72
            else:
                new_rate = base_new_rate * repeat_rate_mult + (1 - repeat_rate_mult) * 0.45

            use_new = rng.random() < new_rate or len(ordered_customers) == 0
            if use_new and len(ordered_customers) < len(all_customer_ids):
                # Pick a customer not yet ordered
                unordered = [cid for cid in all_customer_ids if cid not in ordered_customers]
                if unordered:
                    cust_id = int(rng.choice(unordered))
                    ordered_customers.add(cust_id)
                    is_new = True
                else:
                    cust_id = int(rng.choice(all_customer_ids))
                    is_new = False
            else:
                # Returning customer
                if ordered_customers:
                    cust_id = int(rng.choice(list(ordered_customers)))
                else:
                    cust_id = int(rng.choice(all_customer_ids))
                    ordered_customers.add(cust_id)
                is_new = False

            if is_new:
                ev["new_customers"] += 1

            segment = seg_map.get(cust_id, "one_time")
            channel, source_value, utm_source, utm_medium = _pick_channel(current_date, rng)

            # Order timestamp: random time during the day
            hour = int(rng.integers(0, 24))
            minute = int(rng.integers(0, 60))
            order_ts = datetime(
                current_date.year, current_date.month, current_date.day,
                hour, minute, 0, tzinfo=timezone.utc
            )

            # AOV multiplier
            aov_mult = 1.0
            if is_bfcm:
                aov_mult = s1.AOV_MULTIPLIER

            net_amount = _sample_order_value(segment, base_aov, rng, aov_mult)

            # Build line items
            lines = _generate_line_items(
                order_id, net_amount, variants_df, products_df, current_date, rng
            )
            actual_subtotal = sum(r["price"] * r["quantity"] for r in lines)
            actual_discount = sum(r["total_discount"] for r in lines)
            actual_tax = sum(
                sum(tl["price"] for tl in json.loads(r["tax_lines"]))
                for r in lines
            )
            shipping = round(float(rng.choice([0.0, 7.95, 9.95, 14.95], p=[0.35, 0.30, 0.25, 0.10])), 2)
            net_total = round(actual_subtotal - actual_discount + actual_tax + shipping, 2)

            # Discount code
            discount_codes_raw = "[]"
            primary_discount_code = None
            if is_bfcm:
                dc = s1.get_discount_code(rng)
                if dc:
                    discount_codes_raw = json.dumps([dc])
                    primary_discount_code = dc["code"]

            fin_status = str(rng.choice(FINANCIAL_STATUSES, p=FIN_STATUS_WEIGHTS))
            cancelled_at = None
            if fin_status == "voided":
                cancelled_at = (order_ts + timedelta(hours=int(rng.integers(1, 24)))).isoformat()

            device = str(rng.choice(DEVICE_TYPES, p=DEVICE_WEIGHTS))
            browser = str(rng.choice(BROWSERS, p=BROWSER_WEIGHTS))
            browser_width = DEVICE_WIDTHS[device] + int(rng.integers(-20, 20))
            ua = f"Mozilla/5.0 ({device}) {browser}/120.0"
            country_code = cust_country.get(cust_id, "US")
            province_code = cust_province.get(cust_id, "CA")

            note_attrs = _build_note_attributes(utm_source, utm_medium, None)
            source_name = source_value.split(" / ")[0] if source_value else "web"
            if source_name in ("facebook", "google", "(direct)"):
                source_name = "web"

            # Tags
            tags = None
            if rng.random() < 0.05:
                tags = "vip"

            order_rows.append({
                "id": order_id,
                "name": f"#{order_id - 5000000 + 1000:05d}",
                "order_number": order_id - 5000000 + 1000,
                "customer_id": cust_id,
                "created_at": order_ts.isoformat(),
                "updated_at": order_ts.isoformat(),
                "processed_at": order_ts.isoformat(),
                "closed_at": (order_ts + timedelta(days=7)).isoformat() if fin_status == "paid" else None,
                "cancelled_at": cancelled_at,
                "financial_status": fin_status,
                "fulfillment_status": "fulfilled" if fin_status in ("paid", "partially_refunded") else None,
                "email": cust_email.get(cust_id),
                "subtotal_price": round(actual_subtotal, 2),
                "total_discounts": round(actual_discount, 2),
                "total_tax": round(actual_tax, 2),
                "total_shipping_price_set_shop_money_amount": shipping,
                "total_tip_received": 0.0,
                "total_price": net_total,
                "currency": "USD",
                "source_name": source_name,
                "landing_site": f"https://northwindco.com/collections/{channel}",
                "landing_site_ref": f"https://{utm_source}.com" if utm_source else None,
                "cart_token": f"cart_{order_id:016x}",
                "note_attributes": note_attrs,
                "client_details_browser_width": browser_width,
                "client_details_user_agent": ua,
                "browser_ip": "0.0.0.0",  # hashed immediately in staging; placeholder
                "test": False,
                "tags": tags,
                "note": None,
                "discount_codes": discount_codes_raw,
                "shipping_address_country_code": country_code,
                "shipping_address_province_code": province_code,
                "billing_address_country_code": country_code,
            })

            line_rows.extend(lines)
            ev["gmv"] += net_total
            ev["order_count"] += 1

            # Transaction
            gateway = str(rng.choice(PAYMENT_GATEWAYS, p=GATEWAY_WEIGHTS))
            txn_cb  = str(rng.choice(CARD_BRANDS, p=CARD_WEIGHTS)) if gateway != "paypal" else None
            txn_cw  = str(rng.choice(CARD_WALLETS)) if gateway != "paypal" and rng.random() < 0.15 else None
            txn_rows.append({
                "id":       txn_id,
                "order_id": order_id,
                "kind":     "sale",
                "status":   "success" if fin_status not in ("voided",) else "failure",
                "created_at":  order_ts.isoformat(),
                "processed_at": order_ts.isoformat(),
                "amount":   net_total,
                "currency": "USD",
                "gateway":  gateway,
                "payment_method_type": "credit_card" if gateway != "paypal" else "paypal",
                # Fivetran-flattened payment_method_details columns (§6.4)
                "payment_details_credit_card_company":          txn_cb,
                "payment_details_credit_card_bin":              f"{int(rng.integers(400000, 499999))}" if txn_cb else None,
                "payment_details_credit_card_expiration_month": f"{int(rng.integers(1, 13)):02d}" if txn_cb else None,
                "payment_details_credit_card_expiration_year":  str(rng.choice(CARD_EXP_YEARS)) if txn_cb else None,
                "payment_details_credit_card_wallet":           txn_cw,
                "maximum_refundable": net_total if fin_status == "paid" else 0.0,
                "authorization":      f"auth_{txn_id:012x}" if fin_status != "voided" else None,
                "error_code":         None,
                "message":            None,
                "parent_id":          None,
            })
            txn_id += 1

            # Stripe charge (if gateway is stripe or shopify_payments)
            if gateway in ("stripe", "shopify_payments"):
                sc_id = f"ch_{stripe_charge_id:016x}"
                pm_id = f"pm_{stripe_charge_id:016x}"
                stripe_charge_id += 1
                card_brand  = str(rng.choice(CARD_BRANDS,  p=CARD_WEIGHTS))
                card_wallet = str(rng.choice(CARD_WALLETS)) if rng.random() < 0.15 else None
                card_fund   = str(rng.choice(CARD_FUNDING, p=CARD_FUNDING_W))
                card_last4  = f"{int(rng.integers(1000, 9999))}"
                card_month  = f"{int(rng.integers(1, 13)):02d}"
                card_year   = str(rng.choice(CARD_EXP_YEARS))
                succeeded   = fin_status not in ("voided",)
                stripe_charge_rows.append({
                    "id":              sc_id,
                    "created":         int(order_ts.timestamp()),
                    "amount":          int(net_total * 100),
                    "amount_refunded": 0,
                    "currency":        "usd",
                    "status":          "succeeded" if succeeded else "failed",
                    "livemode":        True,
                    "customer":        None,
                    # Fivetran-flattened payment_method_details — source_col macro
                    # uses these default names when no source_mapping_override set.
                    "payment_method_details_type":        "card",
                    "payment_method_details_card_brand":  card_brand,
                    "payment_method_details_card_last4":  card_last4,
                    "payment_method_details_card_exp_month": card_month,
                    "payment_method_details_card_exp_year":  card_year,
                    "payment_method_details_card_wallet": card_wallet,
                    "metadata_shopify_order_id":          str(order_id),
                    "payment_method":  pm_id,
                    "paid":            succeeded,
                    "captured":        succeeded,
                    "refunded":        False,
                })

            # Refund
            if fin_status in ("refunded", "partially_refunded"):
                refund_ts = order_ts + timedelta(days=int(rng.integers(1, 30)))
                refund_amount = net_total if fin_status == "refunded" else round(net_total * 0.5, 2)

                # Refund transaction VARIANT — required by stg_shopify__refunds → fact_refunds.
                # Must have kind='refund' and status='success' for the amount to be picked up
                # by the LATERAL FLATTEN in fact_refunds. Amount stored as string per Shopify API.
                refund_txn = json.dumps([{
                    "id": txn_id,
                    "kind": "refund",
                    "status": "success",
                    "amount": str(round(refund_amount, 2)),
                    "currency": "USD",
                    "created_at": refund_ts.isoformat(),
                    "processed_at": refund_ts.isoformat(),
                    "gateway": gateway,
                }])

                # Allocate the refund to real order lines so refunded_quantity flows to
                # fact_order_lines (drives Return Rate / units refunded). Full refund returns
                # every line; a partial refund returns the single highest-value line. Fully
                # deterministic (no rng) — keeps order/inventory generation byte-identical.
                refunded_lines = lines if fin_status == "refunded" else [
                    max(lines, key=lambda L: L["price"] * L["quantity"])
                ]
                refund_line_items = json.dumps([
                    {
                        "line_item_id": L["id"],
                        "quantity": int(L["quantity"]),
                        "subtotal": str(round(float(L["price"]) * int(L["quantity"]), 2)),
                    }
                    for L in refunded_lines
                ])

                refund_rows.append({
                    "id": refund_id,
                    "order_id": order_id,
                    "created_at": refund_ts.isoformat(),
                    "note": rng.choice([
                        "Customer return", "Wrong item", "Damaged in transit",
                        "Changed mind", "Quality issue", "Not as described",
                    ]),
                    "processed_at": refund_ts.isoformat(),
                    "restock": bool(rng.random() < 0.70),
                    "transactions": refund_txn,
                    "refund_line_items": refund_line_items,
                })

                # Stripe refund
                if gateway in ("stripe", "shopify_payments") and stripe_charge_rows:
                    last_charge = stripe_charge_rows[-1]
                    last_charge["amount_refunded"] = int(refund_amount * 100)
                    last_charge["refunded"] = True
                    stripe_refund_rows.append({
                        "id":       f"re_{refund_id:016x}",
                        "charge":   last_charge["id"],
                        "amount":   int(refund_amount * 100),
                        "currency": "usd",
                        "status":   "succeeded",
                        "reason":   "requested_by_customer",
                        "created":  int(refund_ts.timestamp()),
                    })
                refund_id += 1

            order_id += 1

        current_date += timedelta(days=1)

    # Build Stripe disputes (chargebacks, ~0.1% of orders)
    stripe_dispute_rows = []
    n_disputes = max(1, int(ev["order_count"] * 0.001))
    dispute_samples = rng.choice(len(stripe_charge_rows), size=min(n_disputes, len(stripe_charge_rows)), replace=False)
    for idx in dispute_samples:
        sc = stripe_charge_rows[int(idx)]
        stripe_dispute_rows.append({
            "id": f"dp_{idx:016x}",
            "charge": sc["id"],
            "amount": sc["amount"],
            "currency": "usd",
            "status": "lost",
            "reason": "fraudulent",
            "created": sc["created"] + 86400 * int(rng.integers(10, 60)),
        })

    # Stripe payment methods
    pm_types = ["card", "card", "card", "card", "klarna", "affirm", "afterpay_clearpay"]
    pm_weights = [0.70, 0.70, 0.70, 0.70, 0.10, 0.08, 0.08]
    n_pms = min(len(stripe_charge_rows), 5000)
    stripe_pm_rows = []
    for i in range(n_pms):
        pm_type  = str(rng.choice(["card", "klarna", "affirm", "afterpay_clearpay"], p=[0.82, 0.10, 0.04, 0.04]))
        is_card  = pm_type == "card"
        cb       = str(rng.choice(CARD_BRANDS,  p=CARD_WEIGHTS))     if is_card else None
        cf       = str(rng.choice(CARD_FUNDING, p=CARD_FUNDING_W))   if is_card else None
        cw       = str(rng.choice(CARD_WALLETS)) if is_card and rng.random() < 0.15 else None
        stripe_pm_rows.append({
            "id":             f"pm_{i:016x}",
            "type":           pm_type,
            "customer":       None,
            "card_brand":     cb,
            "card_last4":     f"{int(rng.integers(1000, 9999))}" if is_card else None,
            "card_exp_month": f"{int(rng.integers(1, 13)):02d}"  if is_card else None,
            "card_exp_year":  str(rng.choice(CARD_EXP_YEARS))    if is_card else None,
            "card_wallet":    cw,
            "card_funding":   cf,
            "card_country":   "US"                                if is_card else None,
            "livemode":       True,
            "created":        int(datetime(2026, 1, 1, tzinfo=timezone.utc).timestamp()) + int(rng.integers(0, 86400 * 365)),
        })

    return {
        "shopify_orders": pd.DataFrame(order_rows),
        "shopify_order_line_items": pd.DataFrame(line_rows),
        "shopify_refunds": pd.DataFrame(refund_rows),
        "shopify_transactions": pd.DataFrame(txn_rows),
        "stripe_charges": pd.DataFrame(stripe_charge_rows),
        "stripe_refunds": pd.DataFrame(stripe_refund_rows),
        "stripe_disputes": pd.DataFrame(stripe_dispute_rows),
        "stripe_payment_methods": pd.DataFrame(stripe_pm_rows),
        "expected_values": ev,
    }
