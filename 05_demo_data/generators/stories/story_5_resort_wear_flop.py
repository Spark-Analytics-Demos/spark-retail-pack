"""
Story 5: Resort Wear line failure (March–May 2026).

Northwind launches an 18-SKU Resort Wear capsule on March 1.
The line underperforms badly — 22% sell-through at 30 days vs. typical 60%.
By May 15, the line moves to clearance at 40% discount.

Effects:
  - Resort Wear SKUs generated with low initial sell-through rate
  - Slow-mover flags fire by mid-April (14 of 18 SKUs)
  - Inventory value tied up in these SKUs is elevated through April/May
  - Clearance discount kicks in May 15 (40% off)
  - Category sell-through rate visible as underperforming in dashboards
"""

from datetime import date

LAUNCH_DATE = date(2026, 3, 1)
SLOW_MOVER_FLAG_DATE = date(2026, 4, 15)
CLEARANCE_START = date(2026, 5, 15)
YEAR_END = date(2026, 12, 31)

SKU_COUNT = 18

# Target sell-through at 30 days (22% vs typical 60%)
SELL_THROUGH_30D = 0.22

# Clearance discount
CLEARANCE_DISCOUNT_PCT = 0.40

# Initial stock per SKU
INITIAL_UNITS_PER_SKU = 80

# Daily sell rate before clearance (very low)
PRE_CLEARANCE_DAILY_SELL_RATE = 0.003   # 0.3% of inventory sold per day

# Daily sell rate during clearance (higher, but still slow)
CLEARANCE_DAILY_SELL_RATE = 0.012

# Resort Wear SKU prefix
SKU_PREFIX = "RW"

# Fraction of SKUs flagged as slow movers by April 15
SLOW_MOVER_FRACTION = 14 / 18  # ~78%


def is_clearance_period(d: date) -> bool:
    return d >= CLEARANCE_START


def get_resort_wear_price_multiplier(d: date) -> float:
    if is_clearance_period(d):
        return 1.0 - CLEARANCE_DISCOUNT_PCT
    return 1.0


def get_daily_sell_rate(d: date) -> float:
    if d < LAUNCH_DATE:
        return 0.0
    if is_clearance_period(d):
        return CLEARANCE_DAILY_SELL_RATE
    return PRE_CLEARANCE_DAILY_SELL_RATE
