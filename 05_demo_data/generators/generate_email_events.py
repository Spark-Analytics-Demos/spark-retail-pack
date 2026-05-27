"""
Generate Klaviyo email engagement events and campaign/flow metadata.

Produces:
  klaviyo/events.csv
  klaviyo/campaigns.csv
  klaviyo/flows.csv
"""

import json
import pandas as pd
import numpy as np
from datetime import datetime, timedelta, timezone

from stories import story_3_pricing_churn as s3

# Base engagement rates (Klaviyo events per delivered email)
BASE_DELIVERED_RATE = 0.98     # 98% of sends are delivered
BASE_OPEN_RATE = 0.38          # open rate on delivered
BASE_CLICK_RATE = 0.042        # click rate on opens
BASE_UNSUBSCRIBE_RATE = 0.004  # unsubscribe rate on delivered
BASE_CONVERSION_RATE = 0.016   # placed order via email click


def generate_email_events(
    rng: np.random.Generator,
    cfg: dict,
    customers_data: dict,
    marketing_config: dict,
) -> dict:
    """
    Returns dict with DataFrames: klaviyo_events, klaviyo_campaigns, klaviyo_flows.
    """
    tier = cfg.get("tier", "medium")
    klaviyo_profiles = customers_data["klaviyo_profiles"]

    if klaviyo_profiles.empty:
        return {
            "klaviyo_events": pd.DataFrame(),
            "klaviyo_campaigns": pd.DataFrame(),
            "klaviyo_flows": pd.DataFrame(),
        }

    campaigns = marketing_config.get("klaviyo_campaigns", [])
    flows = marketing_config.get("klaviyo_flows", [])

    # For Small tier, sample profiles to limit event volume
    sample_rate = {"small": 0.30, "medium": 1.0, "large": 1.0}.get(tier, 1.0)
    if sample_rate < 1.0:
        n_sample = max(1, int(len(klaviyo_profiles) * sample_rate))
        profiles_to_use = klaviyo_profiles.sample(n=n_sample,
                                                   random_state=int(rng.integers(0, 2**31)))
    else:
        profiles_to_use = klaviyo_profiles

    profile_ids = profiles_to_use["id"].values
    profile_emails = dict(zip(profiles_to_use["id"], profiles_to_use.get("email", pd.Series())))

    event_rows = []
    event_id_counter = 1

    # Campaign sends
    campaign_rows = []
    for camp in campaigns:
        send_dt = datetime.fromisoformat(camp["send_date"] + "T10:00:00+00:00")
        campaign_rows.append({
            "id": camp["id"],
            "name": camp["name"],
            "subject": camp["subject"],
            "status": camp["status"],
            "_fivetran_synced": datetime(2026, 12, 31, tzinfo=timezone.utc).isoformat(),
        })

        # Subsample profiles to send to (not all profiles receive every campaign)
        send_rate = min(1.0, float(rng.uniform(0.55, 0.85)))
        n_send = max(1, int(len(profile_ids) * send_rate))
        send_indices = rng.choice(len(profile_ids), size=n_send, replace=False)

        for idx in send_indices:
            pid = str(profile_ids[int(idx)])
            event_ts = send_dt + timedelta(minutes=int(rng.integers(0, 120)))

            # Check if this is a sweater campaign (story 3 churn effect)
            is_sweater_campaign = "sweater" in camp["name"].lower() or "sweater" in camp.get("subject", "").lower()
            ctr_mult = 1.0
            if is_sweater_campaign:
                ctr_mult = s3.get_sweater_email_ctr_multiplier(send_dt.date())

            # Delivered
            if rng.random() < BASE_DELIVERED_RATE:
                event_rows.append({
                    "id": f"EV{event_id_counter:012d}",
                    "event_name": "Received Email",
                    "profile_id": pid,
                    "datetime": event_ts.isoformat(),
                    "campaign_id": camp["id"],
                    "flow_id": None,
                    "event_properties": json.dumps({"campaign_name": camp["name"]}),
                })
                event_id_counter += 1

                # Opened
                if rng.random() < BASE_OPEN_RATE:
                    open_ts = event_ts + timedelta(minutes=int(rng.integers(5, 720)))
                    event_rows.append({
                        "id": f"EV{event_id_counter:012d}",
                        "event_name": "Opened Email",
                        "profile_id": pid,
                        "datetime": open_ts.isoformat(),
                        "campaign_id": camp["id"],
                        "flow_id": None,
                        "event_properties": json.dumps({"campaign_name": camp["name"]}),
                    })
                    event_id_counter += 1

                    # Clicked
                    if rng.random() < BASE_CLICK_RATE * ctr_mult:
                        click_ts = open_ts + timedelta(seconds=int(rng.integers(5, 600)))
                        event_rows.append({
                            "id": f"EV{event_id_counter:012d}",
                            "event_name": "Clicked Email",
                            "profile_id": pid,
                            "datetime": click_ts.isoformat(),
                            "campaign_id": camp["id"],
                            "flow_id": None,
                            "event_properties": json.dumps({
                                "campaign_name": camp["name"],
                                "url": "https://northwindco.com/collections/new-arrivals",
                            }),
                        })
                        event_id_counter += 1

            # Unsubscribe
            if rng.random() < BASE_UNSUBSCRIBE_RATE:
                unsub_ts = event_ts + timedelta(hours=int(rng.integers(1, 72)))
                event_rows.append({
                    "id": f"EV{event_id_counter:012d}",
                    "event_name": "Unsubscribed",
                    "profile_id": pid,
                    "datetime": unsub_ts.isoformat(),
                    "campaign_id": camp["id"],
                    "flow_id": None,
                    "event_properties": json.dumps({}),
                })
                event_id_counter += 1

    # Flow triggers (welcome series, abandoned cart, post-purchase)
    flow_rows = []
    for flow in flows:
        flow_rows.append({
            "id": flow["id"],
            "name": flow["name"],
            "status": flow["status"],
            "_fivetran_synced": datetime(2026, 12, 31, tzinfo=timezone.utc).isoformat(),
        })

        # Welcome series: sent to ~40% of profiles (new subscriber trigger)
        if flow["id"] == "FL001":
            n_welcome = max(1, int(len(profile_ids) * 0.40))
            welcome_indices = rng.choice(len(profile_ids), size=n_welcome, replace=False)
            for idx in welcome_indices:
                pid = str(profile_ids[int(idx)])
                base_dt = datetime(2026, 1, 1, tzinfo=timezone.utc) + timedelta(
                    days=int(rng.integers(0, 365)),
                    hours=int(rng.integers(8, 20)),
                )
                for email_def in flow.get("emails", []):
                    delay_days = email_def.get("day", 0)
                    delay_hours = email_def.get("hour", 0)
                    send_dt = base_dt + timedelta(days=delay_days, hours=delay_hours)
                    if send_dt.year > 2026:
                        break
                    if rng.random() < BASE_DELIVERED_RATE:
                        event_rows.append({
                            "id": f"EV{event_id_counter:012d}",
                            "event_name": "Received Email",
                            "profile_id": pid,
                            "datetime": send_dt.isoformat(),
                            "campaign_id": None,
                            "flow_id": flow["id"],
                            "event_properties": json.dumps({"flow_name": flow["name"]}),
                        })
                        event_id_counter += 1
                        if rng.random() < BASE_OPEN_RATE * 1.2:  # welcome emails open better
                            open_dt = send_dt + timedelta(minutes=int(rng.integers(10, 480)))
                            event_rows.append({
                                "id": f"EV{event_id_counter:012d}",
                                "event_name": "Opened Email",
                                "profile_id": pid,
                                "datetime": open_dt.isoformat(),
                                "campaign_id": None,
                                "flow_id": flow["id"],
                                "event_properties": json.dumps({"flow_name": flow["name"]}),
                            })
                            event_id_counter += 1

        # Abandoned cart: ~15% of sessions
        elif flow["id"] == "FL002":
            n_cart = max(1, int(len(profile_ids) * 0.15))
            cart_indices = rng.choice(len(profile_ids), size=n_cart, replace=False)
            for idx in cart_indices:
                pid = str(profile_ids[int(idx)])
                base_dt = datetime(2026, 1, 1, tzinfo=timezone.utc) + timedelta(
                    days=int(rng.integers(0, 365)),
                )
                for email_def in flow.get("emails", []):
                    delay_hours = email_def.get("hour", 0)
                    send_dt = base_dt + timedelta(hours=delay_hours)
                    if send_dt.year > 2026:
                        break
                    event_rows.append({
                        "id": f"EV{event_id_counter:012d}",
                        "event_name": "Received Email",
                        "profile_id": pid,
                        "datetime": send_dt.isoformat(),
                        "campaign_id": None,
                        "flow_id": flow["id"],
                        "event_properties": json.dumps({"flow_name": flow["name"]}),
                    })
                    event_id_counter += 1

    return {
        "klaviyo_events": pd.DataFrame(event_rows),
        "klaviyo_campaigns": pd.DataFrame(campaign_rows),
        "klaviyo_flows": pd.DataFrame(flow_rows),
    }
