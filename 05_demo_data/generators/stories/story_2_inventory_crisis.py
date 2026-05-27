"""
Story 2: Inventory crisis on Heritage Denim Jacket (April 8–25, 2026).

The SKU HJ-001-MED-BLU goes out of stock on April 8 due to:
  - Unexpected demand spike from a fashion week mention
  - Delayed supplier shipment (arrives April 26)

Effects:
  - Inventory level for HJ-001-MED-BLU goes to 0 on April 8
  - SKU is unavailable for sale April 8–25 (17 days)
  - Outerwear/Jackets revenue dips ~18% during the stockout window
  - Email "Back in Stock" notification fires April 26 → engagement spike
"""

from datetime import date

STOCKOUT_SKU = "OJ-001-MED-BLU"
STOCKOUT_VARIANT_ID = 2000001
STOCKOUT_PRODUCT_ID = 1000001
STOCKOUT_INVENTORY_ITEM_ID = 3000001

STOCKOUT_START = date(2026, 4, 8)
STOCKOUT_END = date(2026, 4, 25)
RESTOCK_DATE = date(2026, 4, 26)

# Pre-stockout inventory level
PRE_STOCKOUT_UNITS = 47

# Restock quantity
RESTOCK_UNITS = 120

# Revenue impact on Outerwear/Jackets subcategory during stockout
OUTERWEAR_REVENUE_SUPPRESSION = 0.18  # 18% revenue drop in category

# Back-in-stock email opens spike
BACK_IN_STOCK_EMAIL_OPEN_SPIKE_FACTOR = 3.2


def is_stockout_period(d: date) -> bool:
    return STOCKOUT_START <= d <= STOCKOUT_END


def units_available(d: date) -> int:
    if d < STOCKOUT_START:
        return PRE_STOCKOUT_UNITS
    if is_stockout_period(d):
        return 0
    return RESTOCK_UNITS


def should_suppress_jacket_order(d: date, rng) -> bool:
    """Returns True if a Jackets order should be suppressed (due to stockout of top SKU)."""
    if not is_stockout_period(d):
        return False
    return rng.random() < OUTERWEAR_REVENUE_SUPPRESSION
