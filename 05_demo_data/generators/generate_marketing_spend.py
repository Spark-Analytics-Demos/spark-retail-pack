"""
Generate Meta Ads performance tables.

Produces:
  meta_ads/daily_insights.csv
  meta_ads/campaigns.csv
  meta_ads/ad_sets.csv
  meta_ads/ads.csv

Google Ads spend is also generated as a separate CSV (source_system='generated')
per §9.3 — not a real connector in v1.
"""

import json
import math
import pandas as pd
import numpy as np
from datetime import date, datetime, timedelta, timezone

from stories import story_1_black_friday as s1
from stories import story_4_viral_moment as s4


# Monthly Meta Ads spend multipliers (roughly follow seasonal demand)
MONTHLY_SPEND_MULT = {
    1: 0.82, 2: 0.78, 3: 0.90, 4: 0.92, 5: 0.98,
    6: 1.02, 7: 0.90, 8: 0.95, 9: 1.15, 10: 1.10,
    11: 1.80,  # BFCM ramp
    12: 1.45,
}

# CPM baselines ($) — varies by objective
CPM_BY_OBJECTIVE = {
    "REACH": 6.50,
    "CONVERSIONS": 14.20,
}
# CTR baselines
CTR_BY_OBJECTIVE = {
    "REACH": 0.008,
    "CONVERSIONS": 0.022,
}


def generate_marketing_spend(
    rng: np.random.Generator,
    cfg: dict,
    marketing_config: dict,
    company: dict,
) -> dict:
    """
    Returns dict with DataFrames: meta_daily_insights, meta_campaigns,
    meta_ad_sets, meta_ads.
    """
    meta_campaigns_cfg = marketing_config.get("meta_campaigns", [])
    annual_meta_spend = marketing_config.get("annual_spend", {}).get("meta_ads_usd", 1_800_000)

    # Scale spend to the tier. The campaign daily_budgets in marketing_calendar.yml
    # are calibrated for the MEDIUM tier (~85K customers, §9.3). Without scaling,
    # small-tier runs spend the same absolute dollars against ~24x fewer customers,
    # so CAC/ROAS come out wildly off (CAC ~$1.6K, ROAS ~0.6). Scaling by the tier's
    # customer count vs the medium baseline keeps CAC/ROAS realistic at every tier.
    MEDIUM_CUSTOMER_COUNT = 85_000
    spend_scale = cfg.get("customer_count", MEDIUM_CUSTOMER_COUNT) / MEDIUM_CUSTOMER_COUNT

    start_date = date(2026, 1, 1)
    end_date = date(2026, 12, 31)

    # Build flat campaign/adset/ad lists
    campaign_rows = []
    adset_rows = []
    ad_rows = []

    sync_ts_str = datetime(2026, 12, 31, tzinfo=timezone.utc).isoformat()

    for camp in meta_campaigns_cfg:
        camp_start = date.fromisoformat(camp["start_date"])
        camp_end   = date.fromisoformat(camp["end_date"])
        n_days = max(1, (camp_end - camp_start).days)
        lifetime_budget = round(camp.get("daily_budget_usd", 0) * spend_scale * n_days, 2)
        campaign_rows.append({
            "id":              camp["id"],
            "name":            camp["name"],
            "objective":       camp["objective"],
            "status":          camp["status"],
            "account_id":      company["meta_ads"]["account_id"],
            "buying_type":     "AUCTION",
            "daily_budget":    camp.get("daily_budget_usd", 0) * spend_scale * 100,  # cents
            "lifetime_budget": 0,
            "start_time":      datetime(camp_start.year, camp_start.month, camp_start.day, tzinfo=timezone.utc).isoformat(),
            "stop_time":       datetime(camp_end.year,   camp_end.month,   camp_end.day,   tzinfo=timezone.utc).isoformat(),
            "created_time":    datetime(camp_start.year, camp_start.month, camp_start.day, tzinfo=timezone.utc).isoformat(),
            "updated_time":    sync_ts_str,
            "_fivetran_synced": sync_ts_str,
        })
        for adset in camp.get("ad_sets", []):
            adset_budget = round(camp.get("daily_budget_usd", 0) * spend_scale / max(1, len(camp.get("ad_sets", [camp]))), 2)
            adset_rows.append({
                "id":                adset["id"],
                "campaign_id":       camp["id"],
                "name":              adset["name"],
                "status":            adset["status"],
                "daily_budget":      adset_budget * 100,  # cents
                "bid_amount":        None,
                "billing_event":     "IMPRESSIONS",
                "optimization_goal": "OFFSITE_CONVERSIONS" if camp["objective"] == "CONVERSIONS" else "REACH",
                "start_time":        datetime(camp_start.year, camp_start.month, camp_start.day, tzinfo=timezone.utc).isoformat(),
                "end_time":          datetime(camp_end.year,   camp_end.month,   camp_end.day,   tzinfo=timezone.utc).isoformat(),
                "created_time":      datetime(camp_start.year, camp_start.month, camp_start.day, tzinfo=timezone.utc).isoformat(),
                "updated_time":      sync_ts_str,
                "_fivetran_synced":  sync_ts_str,
            })
            for ad in adset.get("ads", []):
                ad_rows.append({
                    "id":           ad["id"],
                    "campaign_id":  camp["id"],
                    "adset_id":     adset["id"],
                    "name":         ad["name"],
                    "status":       ad["status"],
                    "creative_id":  f"CR{ad['id']}",
                    "created_time": datetime(camp_start.year, camp_start.month, camp_start.day, tzinfo=timezone.utc).isoformat(),
                    "updated_time": sync_ts_str,
                    "_fivetran_synced": sync_ts_str,
                })

    # Daily insights: one row per active ad per active day
    insight_rows = []
    current_date = start_date
    while current_date <= end_date:
        monthly_mult = MONTHLY_SPEND_MULT[current_date.month]

        # BFCM spike
        if s1.is_bfcm_date(current_date):
            monthly_mult *= s1.get_day_multiplier(current_date) * 0.35  # Meta share of BFCM

        # Viral: ROAS boost (more conversions per dollar)
        viral_roas_boost = 1.0
        if s4.is_viral_period(current_date):
            viral_roas_boost = 1.0 + (s4.get_viral_day_multiplier(current_date) - 1.0) * 0.20

        for camp in meta_campaigns_cfg:
            camp_start = date.fromisoformat(camp["start_date"])
            camp_end = date.fromisoformat(camp["end_date"])
            if not (camp_start <= current_date <= camp_end):
                continue

            daily_budget = camp["daily_budget_usd"] * spend_scale * monthly_mult

            for adset in camp.get("ad_sets", []):
                for ad in adset.get("ads", []):
                    # Split budget evenly across ads in this campaign
                    n_ads_in_camp = sum(len(a.get("ads", [])) for a in camp.get("ad_sets", []))
                    n_ads_in_camp = max(1, n_ads_in_camp)
                    ad_spend = daily_budget / n_ads_in_camp

                    # Add small random noise
                    noise = float(rng.normal(0, ad_spend * 0.08))
                    ad_spend = max(0.50, round(ad_spend + noise, 2))

                    objective = camp["objective"]
                    cpm = CPM_BY_OBJECTIVE.get(objective, 12.0) * float(rng.normal(1.0, 0.12))
                    cpm = max(2.0, cpm)
                    ctr = CTR_BY_OBJECTIVE.get(objective, 0.015) * float(rng.normal(1.0, 0.15))
                    ctr = max(0.001, ctr)

                    impressions = int(ad_spend / cpm * 1000)
                    clicks = int(impressions * ctr)
                    reach = int(impressions * float(rng.uniform(0.72, 0.88)))
                    link_clicks = int(clicks * float(rng.uniform(0.65, 0.85)))

                    # Platform-reported conversions
                    conv_rate = 0.025 * viral_roas_boost if objective == "CONVERSIONS" else 0.005
                    conversions = int(link_clicks * conv_rate * float(rng.normal(1.0, 0.20)))
                    conv_value = round(conversions * float(rng.uniform(85, 160)), 2)

                    actions = json.dumps([{"action_type": "purchase", "value": str(conversions)}])
                    action_values = json.dumps([{"action_type": "purchase", "value": str(conv_value)}])

                    insight_rows.append({
                        "date_start": current_date.isoformat(),
                        "campaign_id": camp["id"],
                        "ad_set_id": adset["id"],
                        "ad_id": ad["id"],
                        "spend": ad_spend,
                        "impressions": max(0, impressions),
                        "clicks": max(0, clicks),
                        "reach": max(0, reach),
                        "inline_link_clicks": max(0, link_clicks),
                        "actions": actions,
                        "action_values": action_values,
                    })

        current_date += timedelta(days=1)

    return {
        "meta_daily_insights": pd.DataFrame(insight_rows),
        "meta_campaigns": pd.DataFrame(campaign_rows),
        "meta_ad_sets": pd.DataFrame(adset_rows),
        "meta_ads": pd.DataFrame(ad_rows),
    }
