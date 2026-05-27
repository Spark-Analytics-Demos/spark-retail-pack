"""
Story 4: Viral moment — Cargo Field Pants (September 14–28, 2026).

A mid-tier influencer (~280K followers) posts an unboxing video on September 14.
The post goes viral, driving a 2-week acquisition surge.

Effects:
  - New customer count spikes from ~70/day to ~600/day for two weeks
  - Cargo Field Pants (BP-001-REG-KHA) becomes #1 SKU in the period
  - Cargo Field Pants goes out of stock September 22, back in stock October 8
  - Acquisition channel mix shifts toward Referral and Direct
  - Reported CAC drops because existing spend captures more conversions
  - Revenue spike concentrated in Bottoms/Pants subcategory
"""

from datetime import date

VIRAL_SKU = "BP-001-REG-KHA"
VIRAL_VARIANT_ID = 2000002
VIRAL_PRODUCT_ID = 1000002
VIRAL_INVENTORY_ITEM_ID = 3000002

VIRAL_START = date(2026, 9, 14)
VIRAL_END = date(2026, 9, 28)
STOCKOUT_DATE = date(2026, 9, 22)
RESTOCK_DATE = date(2026, 10, 8)

# Pre-viral inventory
PRE_VIRAL_UNITS = 142

# Viral order volume multiplier per day (on top of seasonal baseline)
VIRAL_ORDER_MULTIPLIER = {
    date(2026, 9, 14): 3.2,
    date(2026, 9, 15): 5.8,
    date(2026, 9, 16): 7.4,
    date(2026, 9, 17): 8.1,
    date(2026, 9, 18): 7.2,
    date(2026, 9, 19): 6.5,
    date(2026, 9, 20): 5.8,
    date(2026, 9, 21): 5.1,
    date(2026, 9, 22): 4.2,  # stockout hits — spike continues on other items
    date(2026, 9, 23): 3.8,
    date(2026, 9, 24): 3.4,
    date(2026, 9, 25): 3.0,
    date(2026, 9, 26): 2.6,
    date(2026, 9, 27): 2.2,
    date(2026, 9, 28): 1.8,
}

# Acquisition channel shift during viral window
CHANNEL_OVERRIDES = {
    "referral":       0.35,
    "direct":         0.28,
    "organic_search": 0.18,
    "meta":           0.14,
    "google_ads":     0.05,
}

# Cargo pants probability of being in an order during viral window (increases sharply)
CARGO_PANTS_ORDER_PROBABILITY = 0.58  # vs. normal ~3%

# Restock quantity
RESTOCK_UNITS = 200


def is_viral_period(d: date) -> bool:
    return VIRAL_START <= d <= VIRAL_END


def is_cargo_pants_available(d: date) -> bool:
    if d < VIRAL_START:
        return True
    if STOCKOUT_DATE <= d < RESTOCK_DATE:
        return False
    return True


def get_viral_day_multiplier(d: date) -> float:
    return VIRAL_ORDER_MULTIPLIER.get(d, 1.0)
