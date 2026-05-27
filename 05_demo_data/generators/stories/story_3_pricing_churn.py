"""
Story 3: Sweater pricing churn (June–August 2026).

Northwind raised prices on the Sweaters subcategory by ~12% on June 1, 2026.
Customer dissatisfaction reduces repeat purchase rate through summer.

Effects:
  - Sweater prices increase 12% from June 1
  - Repeat purchase rate drops from ~28% in May to ~22% in July, recovering to ~26% by September
  - Email CTR on sweater campaigns drops from ~4.2% to ~2.8% in July
  - June 2026 acquisition cohort underperforms on LTV
"""

from datetime import date

PRICE_CHANGE_DATE = date(2026, 6, 1)
PRICE_INCREASE_PCT = 0.12

# Sweater-specific price multiplier by month
SWEATER_PRICE_MULTIPLIER = {
    1: 1.00, 2: 1.00, 3: 1.00, 4: 1.00, 5: 1.00,
    6: 1.12, 7: 1.12, 8: 1.12, 9: 1.12, 10: 1.12, 11: 1.12, 12: 1.12,
}

# Repeat purchase rate multiplier during churn window
REPEAT_RATE_MULTIPLIER = {
    1: 1.00, 2: 1.00, 3: 1.00, 4: 1.00, 5: 1.00,
    6: 0.95,  # churn starts
    7: 0.79,  # trough
    8: 0.85,
    9: 0.93,  # recovery
    10: 1.00, 11: 1.00, 12: 1.00,
}

# Email CTR suppression on sweater campaigns during churn
SWEATER_EMAIL_CTR_MULTIPLIER = {
    1: 1.00, 2: 1.00, 3: 1.00, 4: 1.00, 5: 1.00,
    6: 0.85,
    7: 0.67,  # worst month
    8: 0.74,
    9: 0.88,
    10: 1.00, 11: 1.00, 12: 1.00,
}


def get_sweater_price_multiplier(d: date) -> float:
    return SWEATER_PRICE_MULTIPLIER.get(d.month, 1.0)


def get_repeat_rate_multiplier(d: date) -> float:
    return REPEAT_RATE_MULTIPLIER.get(d.month, 1.0)


def get_sweater_email_ctr_multiplier(d: date) -> float:
    return SWEATER_EMAIL_CTR_MULTIPLIER.get(d.month, 1.0)
