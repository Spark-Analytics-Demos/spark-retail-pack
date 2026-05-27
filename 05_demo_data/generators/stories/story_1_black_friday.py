"""
Story 1: Black Friday / Cyber Monday spike (November 28 – December 1, 2026).

Peak day multipliers vs. seasonal baseline:
  Nov 28 (Black Friday):   8.2× → ~1,650 orders (Medium tier)
  Nov 29 (Saturday):       6.8×
  Nov 30 (Cyber Monday... wait, Sunday):  5.5×
  Dec 1  (Cyber Monday):   7.1×

Additional effects:
  - Discount codes injected on 92% of orders (BFCM26, SAVE25, TAKE20)
  - New customer ratio spikes from ~58% to ~78%
  - AOV drops ~15% due to discounting
  - Limited Edition SKUs sell through 95% of stock
  - ~80 SKUs hit stockout by Dec 1
"""

from datetime import date

# Date range for the event
START_DATE = date(2026, 11, 28)
END_DATE = date(2026, 12, 1)

# Per-day order volume multiplier vs. the seasonal baseline (applied on top of monthly + weekly multipliers)
DAY_MULTIPLIERS = {
    date(2026, 11, 28): 8.2,  # Black Friday
    date(2026, 11, 29): 6.8,  # Saturday
    date(2026, 11, 30): 5.5,  # Sunday
    date(2026, 12, 1):  7.1,  # Cyber Monday
}

# Discount codes injected into orders during the event window
DISCOUNT_CODES = [
    {"code": "BFCM26",  "amount": "25.00", "type": "percentage"},
    {"code": "SAVE25",  "amount": "25.00", "type": "percentage"},
    {"code": "TAKE20",  "amount": "20.00", "type": "percentage"},
    {"code": "FREESHIPBF", "amount": "0.00", "type": "shipping"},
]
DISCOUNT_CODE_WEIGHTS = [0.45, 0.25, 0.20, 0.10]
DISCOUNT_APPLICATION_RATE = 0.92   # 92% of BFCM orders have a discount code

# New customer acquisition spike: normal baseline * this factor during the window
NEW_CUSTOMER_RATE_OVERRIDE = 0.78  # vs. typical ~0.58

# AOV reduction from discounting
AOV_MULTIPLIER = 0.87

# Source name for BFCM orders (Shopify source_name field)
SOURCE_NAME = "web"

# Acquisition channel shift during BFCM (more organic/email, less paid)
CHANNEL_OVERRIDES = {
    "meta":           0.28,
    "email":          0.22,
    "organic_search": 0.24,
    "direct":         0.18,
    "referral":       0.05,
    "google_ads":     0.03,
}


def is_bfcm_date(d: date) -> bool:
    return START_DATE <= d <= END_DATE


def get_day_multiplier(d: date) -> float:
    return DAY_MULTIPLIERS.get(d, 1.0)


def get_discount_code(rng) -> dict | None:
    if rng.random() > DISCOUNT_APPLICATION_RATE:
        return None
    idx = rng.choice(len(DISCOUNT_CODES), p=DISCOUNT_CODE_WEIGHTS)
    return DISCOUNT_CODES[idx]
