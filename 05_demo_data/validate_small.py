"""
validate_small.py — KPI smoke-test against the small-tier demo dataset.

Runs locally without Snowflake. Computes KPIs directly from raw source CSVs
and checks them against the expected_values_snapshot.yml.

Two calculation modes:
  SNAPSHOT  — matches the generator's own expected_values computation
              (total_price all orders; used to verify CSV round-trip integrity)
  KPI_SPEC  — per the design doc KPI definitions
              (subtotal-discounts, non-voided only; this is what dbt should produce)

Usage:
  python validate_small.py
"""

import json
import pandas as pd
from pathlib import Path

BASE = Path(__file__).parent / "datasets" / "small"

orders = pd.read_csv(BASE / "shopify/orders.csv", parse_dates=["created_at"])
items = pd.read_csv(BASE / "shopify/order_line_items.csv")
customers = pd.read_csv(BASE / "shopify/customers.csv", parse_dates=["created_at"])
refunds_df = pd.read_csv(BASE / "shopify/refunds.csv")
meta = pd.read_csv(BASE / "meta_ads/daily_insights.csv", parse_dates=["date_start"])
klaviyo = pd.read_csv(BASE / "klaviyo/events.csv", parse_dates=["datetime"])
inv = pd.read_csv(
    BASE / "bronze_pre_aggregated/inventory_snapshots.csv",
    parse_dates=["snapshot_date"],
)

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"

failures = []


def check(label, got, expected, tolerance_pct=0.0):
    if tolerance_pct == 0.0:
        ok = got == expected
        diff_str = f"exact"
    else:
        diff_pct = abs(got - expected) / max(abs(expected), 1e-9) * 100
        ok = diff_pct <= tolerance_pct
        diff_str = f"diff {diff_pct:.3f}% (tol {tolerance_pct}%)"
    status = PASS if ok else FAIL
    print(f"  {status}  {label}")
    print(f"         got={got!r}  expected={expected!r}  ({diff_str})")
    if not ok:
        failures.append(label)


# ── Snapshot assertions (generator integrity) ──────────────────────────────
print("\n=== 1. Snapshot assertions (generator integrity) ===")
print("    Checks that CSVs match what the generator reported in expected_values_snapshot.yml\n")

check("order_count (all orders incl. voided)",
      len(orders), 6095)
check("new_customers (total distinct customers)",
      len(customers), 3500)
gmv_gen = round(orders["total_price"].sum(), 2)
check("gmv_usd (total_price all orders — generator calculation)",
      gmv_gen, 2438723.89)

# ── KPI-spec computations (per design doc definitions) ─────────────────────
print("\n=== 2. KPI-spec computations (per design doc — what dbt should produce) ===\n")

non_voided = orders[orders["financial_status"] != "voided"]
non_voided_non_test = non_voided[non_voided["test"] == False]

# KPI 1 — GMV: subtotal - discounts, non-cancelled/non-test
gmv_kpi = round((non_voided_non_test["subtotal_price"]
                 - non_voided_non_test["total_discounts"]).sum(), 2)
print(f"  KPI 1  GMV (subtotal-discounts, non-voided):      ${gmv_kpi:>14,.2f}")

# KPI 2 — Net Revenue: GMV - refunds
# Approximate at source level: join refunds back to orders
refunded_orders = orders[orders["financial_status"].isin(["refunded", "partially_refunded"])]
# Generator doesn't track refund amounts granularly in refunds.csv, so use total_price proxy
refund_total = refunded_orders["total_price"].sum() * 0.5  # partial ~ 50%
refund_total_full = orders[orders["financial_status"] == "refunded"]["total_price"].sum()
net_rev_approx = gmv_kpi - refund_total_full  # full refunds only, conservative
print(f"  KPI 2  Net Revenue (approx, full refunds only):   ${net_rev_approx:>14,.2f}")

# KPI 3 — Order Count
order_count_kpi = len(non_voided_non_test)
print(f"  KPI 3  Order Count (non-voided):                  {order_count_kpi:>15,}")

# KPI 4 — AOV
aov = gmv_kpi / order_count_kpi
print(f"  KPI 4  AOV:                                       ${aov:>14,.2f}")

# KPI 9 — Tax Collected
tax = round(non_voided_non_test["total_tax"].sum(), 2)
print(f"  KPI 9  Tax Collected:                             ${tax:>14,.2f}")

# KPI 12 — New Customers (first-order customers in period)
order_counts_per_cust = orders.groupby("customer_id").size()
new_custs = (order_counts_per_cust == 1).sum()
print(f"  KPI 12 New Customers (1 order in dataset):        {new_custs:>15,}")

# KPI 13 — Repeat Customers
repeat_custs = (order_counts_per_cust > 1).sum()
print(f"  KPI 13 Repeat Customers (2+ orders):              {repeat_custs:>15,}")

# KPI 14 — Repeat Purchase Rate
rpr = repeat_custs / len(order_counts_per_cust) * 100
print(f"  KPI 14 Repeat Purchase Rate:                      {rpr:>14.1f}%")

# KPI 19 — Email Engagement Rate
delivered = (klaviyo["event_name"] == "Received Email").sum()
opened = (klaviyo["event_name"] == "Opened Email").sum()
clicked = (klaviyo["event_name"] == "Clicked Email").sum()
engaged = opened + clicked
eng_rate = engaged / delivered * 100 if delivered > 0 else 0
print(f"\n  KPI 19 Email Engagement Rate:")
print(f"         Delivered={delivered:,}  Opened={opened:,}  Clicked={clicked:,}")
print(f"         Engagement Rate = {eng_rate:.1f}%")

# KPI 23 — Stockout Rate (as of 2026-12-31)
eod = inv[inv["snapshot_date"] == inv["snapshot_date"].max()]
sku_total = eod["inventory_item_id"].nunique()
sku_oos = eod[eod["available"] <= 0]["inventory_item_id"].nunique()
stockout_rate = sku_oos / sku_total * 100 if sku_total > 0 else 0
print(f"\n  KPI 23 Stockout Rate (final snapshot {inv['snapshot_date'].max().date()}):")
print(f"         SKUs={sku_total:,}  OOS={sku_oos:,}  Rate={stockout_rate:.1f}%")

# Meta spend
total_spend = round(meta["spend"].sum(), 2)
print(f"\n  Meta Ad spend (total 2026):                       ${total_spend:>14,.2f}")

# ── Story arc checkpoints ──────────────────────────────────────────────────
print("\n=== 3. Story arc checkpoints ===\n")

# Story 1 — BFCM
daily = orders.groupby(orders["created_at"].dt.date).size()
peak_date = daily.idxmax()
peak_orders = daily.max()
bfcm_on_right_day = str(peak_date) == "2026-11-28"
bfcm_enough_volume = int(peak_orders) >= 150
bfcm_ok = bfcm_on_right_day and bfcm_enough_volume
status = PASS if bfcm_ok else FAIL
print(f"  {status}  Story 1 - BFCM peak on 2026-11-28 with >=150 orders")
print(f"         peak_date={peak_date}  peak_orders={peak_orders}  (tol: date=exact, orders>=150)")
if not bfcm_ok:
    failures.append("Story 1 - BFCM")

# Story 4 — Viral moment (Sep spike)
sep_orders = len(orders[orders["created_at"].dt.month == 9])
normal_month_avg = len(orders[
    orders["created_at"].dt.month.isin([1, 2, 3, 5])
]) / 4
viral_multiplier = sep_orders / normal_month_avg
print(f"  Story 4 — Sep orders: {sep_orders}  vs avg non-story month: {normal_month_avg:.0f}")
print(f"           Viral multiplier: {viral_multiplier:.1f}x  (design: ~3x for small tier)")

# Story 2 — Inventory crisis (Apr stockout)
apr_inv = inv[(inv["snapshot_date"] >= "2026-04-08") &
              (inv["snapshot_date"] <= "2026-04-25")]
stockout_skus_apr = apr_inv[apr_inv["available"] <= 0]["inventory_item_id"].nunique()
print(f"  Story 2 — Stockout SKUs in Apr 8–25: {stockout_skus_apr}  (design: ≥1)")

# ── Channel attribution preview ────────────────────────────────────────────
print("\n=== 4. Channel attribution (raw UTM from note_attributes) ===\n")
print("  note: source_name='web' for all orders (Shopify standard)")
print("  UTM params are in note_attributes — parsed by stg_shopify__orders\n")

def parse_utm_source(note_attrs):
    try:
        attrs = json.loads(note_attrs) if isinstance(note_attrs, str) else []
        for a in attrs:
            if a.get("name") == "utm_source":
                return a["value"]
    except Exception:
        pass
    return "(direct)"

orders["utm_source"] = orders["note_attributes"].apply(parse_utm_source)
channel_dist = orders["utm_source"].value_counts()
for ch, cnt in channel_dist.items():
    pct = cnt / len(orders) * 100
    print(f"  {str(ch):<20} {cnt:>5,}  ({pct:.1f}%)")

# ── Summary ────────────────────────────────────────────────────────────────
print("\n" + "=" * 60)
if failures:
    print(f"RESULT: {len(failures)} assertion(s) FAILED:")
    for f in failures:
        print(f"  - {f}")
else:
    print("RESULT: All snapshot assertions PASSED")
print("=" * 60)
