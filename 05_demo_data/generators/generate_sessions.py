"""
Generate GA4 events table — session-level browsing and purchase events.

Each order generates a correlated purchase event. Additional browsing sessions
(page_view, session_start) are generated to fill realistic session volumes.

GA4 event_timestamp format: microseconds since Unix epoch (INT64), per §9.7.
"""

import pandas as pd
import numpy as np
from datetime import date, datetime, timedelta, timezone

from stories import story_1_black_friday as s1
from stories import story_4_viral_moment as s4


# Ratio of browsing sessions per order (sessions that don't convert)
BROWSE_TO_ORDER_RATIO = 64    # Medium: ~7.8M sessions / ~120K orders ≈ 65
GA4_TRAFFIC_SOURCES = [
    ("google", "organic",  "google / organic",  0.28),
    ("facebook.com", "referral", "facebook.com / referral", 0.18),
    ("google", "cpc",      "google / cpc",       0.15),
    ("(direct)", "(none)", "(direct) / (none)",  0.16),
    ("email", "email",     "email / email",       0.08),
    ("instagram.com", "referral", "instagram.com / referral", 0.07),
    ("bing", "organic",    "bing / organic",      0.04),
    ("pinterest.com", "referral", "pinterest.com / referral", 0.02),
    ("tiktok.com", "referral",    "tiktok.com / referral",    0.02),
]
TRAFFIC_WEIGHTS = [s[3] for s in GA4_TRAFFIC_SOURCES]

DEVICE_CATEGORIES = ["mobile", "desktop", "tablet"]
DEVICE_WEIGHTS = [0.52, 0.38, 0.10]
BROWSERS = ["Chrome", "Safari", "Firefox", "Edge", "Samsung Internet"]
BROWSER_WEIGHTS = [0.63, 0.20, 0.08, 0.05, 0.04]
COUNTRIES = ["United States", "Canada", "United Kingdom", "Australia"]
COUNTRY_WEIGHTS = [0.70, 0.15, 0.10, 0.05]

PAGES = [
    "/collections/outerwear", "/collections/tops", "/collections/bottoms",
    "/collections/accessories", "/collections/footwear", "/collections/new-arrivals",
    "/collections/sale", "/products/cargo-field-pants", "/products/heritage-denim-jacket",
    "/", "/pages/about", "/blogs/style-guide",
]


def _ts_micros(dt: datetime) -> int:
    return int(dt.timestamp() * 1_000_000)


def generate_sessions(
    rng: np.random.Generator,
    cfg: dict,
    orders_data: dict,
) -> dict:
    """
    Returns dict with DataFrames: ga4_events, ga4_users.

    For performance, generates at a sampled rate for Small/Medium/Large tiers.
    browse_ratio is scaled down for Small tier to keep output size manageable.
    """
    tier = cfg.get("tier", "medium")
    # Scale browse sessions: Small=8, Medium=64, Large=64
    browse_ratio = {"small": 8, "medium": 64, "large": 64}.get(tier, 64)

    orders_df = orders_data["shopify_orders"]
    event_rows = []
    user_rows = []
    seen_pseudo_ids = set()

    user_pseudo_id_counter = 1

    for _, order in orders_df.iterrows():
        order_ts = datetime.fromisoformat(str(order["created_at"]))
        order_date_str = order_ts.strftime("%Y%m%d")
        event_date = order_ts.date()

        # Each order gets a user_pseudo_id (device-scoped)
        upid = f"GA{user_pseudo_id_counter:020d}"
        user_pseudo_id_counter += 1
        ga_session_id = str(int(order_ts.timestamp()))

        src_idx = int(rng.choice(len(GA4_TRAFFIC_SOURCES), p=TRAFFIC_WEIGHTS))
        src = GA4_TRAFFIC_SOURCES[src_idx]
        device = str(rng.choice(DEVICE_CATEGORIES, p=DEVICE_WEIGHTS))
        browser = str(rng.choice(BROWSERS, p=BROWSER_WEIGHTS))
        country = str(rng.choice(COUNTRIES, p=COUNTRY_WEIGHTS))
        is_new = bool(rng.random() < 0.58)

        # Viral moment: inflate referral traffic
        if s4.is_viral_period(event_date):
            src_idx = int(rng.choice(
                len(GA4_TRAFFIC_SOURCES),
                p=[0.06, 0.32, 0.08, 0.22, 0.06, 0.18, 0.02, 0.04, 0.02],
            ))
            src = GA4_TRAFFIC_SOURCES[src_idx]

        base_ts = order_ts - timedelta(minutes=int(rng.integers(5, 45)))

        # session_start event
        event_rows.append({
            "event_date": event_date.strftime("%Y%m%d"),
            "event_name": "session_start",
            "user_pseudo_id": upid,
            "user_id": None,
            "ga_session_id": ga_session_id,
            "event_timestamp": _ts_micros(base_ts),
            "device__category": device,
            "device__mobile_brand_name": "Apple" if device == "mobile" else None,
            "device__operating_system": "iOS" if device == "mobile" else "Windows",
            "device__web_info__browser": browser,
            "traffic_source__source": src[0],
            "traffic_source__medium": src[1],
            "traffic_source__name": None,
            "geo__country": country,
            "geo__region": None,
            "page_location": "https://northwindco.com/",
            "page_referrer": f"https://{src[0]}.com" if src[0] not in ("(direct)",) else None,
            "page_title": "Northwind Co. — Apparel & Accessories",
            "ecommerce__transaction_id": None,
            "ecommerce__purchase_revenue": None,
            "ecommerce__currency": None,
            "engagement_time_msec": None,
            "is_new_user": is_new,
        })

        # page_view event
        page = str(rng.choice(PAGES))
        event_rows.append({
            "event_date": event_date.strftime("%Y%m%d"),
            "event_name": "page_view",
            "user_pseudo_id": upid,
            "user_id": None,
            "ga_session_id": ga_session_id,
            "event_timestamp": _ts_micros(base_ts + timedelta(seconds=30)),
            "device__category": device,
            "device__mobile_brand_name": "Apple" if device == "mobile" else None,
            "device__operating_system": "iOS" if device == "mobile" else "Windows",
            "device__web_info__browser": browser,
            "traffic_source__source": src[0],
            "traffic_source__medium": src[1],
            "traffic_source__name": None,
            "geo__country": country,
            "geo__region": None,
            "page_location": f"https://northwindco.com{page}",
            "page_referrer": "https://northwindco.com/",
            "page_title": page.strip("/").replace("-", " ").title(),
            "ecommerce__transaction_id": None,
            "ecommerce__purchase_revenue": None,
            "ecommerce__currency": None,
            "engagement_time_msec": int(rng.integers(5000, 180000)),
            "is_new_user": False,
        })

        # purchase event
        event_rows.append({
            "event_date": event_date.strftime("%Y%m%d"),
            "event_name": "purchase",
            "user_pseudo_id": upid,
            "user_id": str(order["customer_id"]),
            "ga_session_id": ga_session_id,
            "event_timestamp": _ts_micros(order_ts),
            "device__category": device,
            "device__mobile_brand_name": "Apple" if device == "mobile" else None,
            "device__operating_system": "iOS" if device == "mobile" else "Windows",
            "device__web_info__browser": browser,
            "traffic_source__source": src[0],
            "traffic_source__medium": src[1],
            "traffic_source__name": None,
            "geo__country": country,
            "geo__region": None,
            "page_location": "https://northwindco.com/checkout/thank-you",
            "page_referrer": "https://northwindco.com/checkout",
            "page_title": "Order Confirmed — Northwind Co.",
            "ecommerce__transaction_id": str(order["id"]),
            "ecommerce__purchase_revenue": float(order["total_price"]),
            "ecommerce__currency": "USD",
            "engagement_time_msec": None,
            "is_new_user": False,
        })

        if upid not in seen_pseudo_ids:
            seen_pseudo_ids.add(upid)
            user_rows.append({"user_pseudo_id": upid, "_fivetran_synced": order_ts.isoformat()})

    # Browsing-only sessions (no purchase) — sampled at browse_ratio × orders
    n_browse = int(len(orders_df) * browse_ratio)
    start_epoch = int(datetime(2026, 1, 1, tzinfo=timezone.utc).timestamp())
    end_epoch = int(datetime(2026, 12, 31, tzinfo=timezone.utc).timestamp())

    for _ in range(n_browse):
        epoch = int(rng.integers(start_epoch, end_epoch))
        browse_ts = datetime.fromtimestamp(epoch, tz=timezone.utc)
        browse_date = browse_ts.date()

        upid = f"GA{user_pseudo_id_counter:020d}"
        user_pseudo_id_counter += 1
        ga_session_id = str(epoch)

        src_idx = int(rng.choice(len(GA4_TRAFFIC_SOURCES), p=TRAFFIC_WEIGHTS))
        src = GA4_TRAFFIC_SOURCES[src_idx]
        device = str(rng.choice(DEVICE_CATEGORIES, p=DEVICE_WEIGHTS))
        browser = str(rng.choice(BROWSERS, p=BROWSER_WEIGHTS))
        country = str(rng.choice(COUNTRIES, p=COUNTRY_WEIGHTS))

        event_rows.append({
            "event_date": browse_date.strftime("%Y%m%d"),
            "event_name": "session_start",
            "user_pseudo_id": upid,
            "user_id": None,
            "ga_session_id": ga_session_id,
            "event_timestamp": _ts_micros(browse_ts),
            "device__category": device,
            "device__mobile_brand_name": "Apple" if device == "mobile" else None,
            "device__operating_system": "iOS" if device == "mobile" else "Windows",
            "device__web_info__browser": browser,
            "traffic_source__source": src[0],
            "traffic_source__medium": src[1],
            "traffic_source__name": None,
            "geo__country": country,
            "geo__region": None,
            "page_location": f"https://northwindco.com{rng.choice(PAGES)}",
            "page_referrer": None,
            "page_title": "Northwind Co. — Apparel & Accessories",
            "ecommerce__transaction_id": None,
            "ecommerce__purchase_revenue": None,
            "ecommerce__currency": None,
            "engagement_time_msec": int(rng.integers(1000, 120000)),
            "is_new_user": bool(rng.random() < 0.60),
        })

        if upid not in seen_pseudo_ids:
            seen_pseudo_ids.add(upid)
            user_rows.append({"user_pseudo_id": upid, "_fivetran_synced": browse_ts.isoformat()})

    return {
        "ga4_events": pd.DataFrame(event_rows),
        "ga4_users": pd.DataFrame(user_rows),
    }
