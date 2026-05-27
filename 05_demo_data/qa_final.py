"""
Final QA script for Northwind Co. demo data (small tier).
Run from: 05_demo_data/generators/
Usage: python ../qa_final.py
"""

import sys
import json
import pandas as pd
from pathlib import Path
from datetime import date

DATASETS = Path(__file__).parent / "datasets" / "small"
ERRORS = []
WARNINGS = []
PASSED = 0


def _is_json(v):
    try:
        json.loads(str(v))
        return True
    except Exception:
        return False


def ok(msg):
    global PASSED
    PASSED += 1
    print(f"  PASS  {msg}")


def fail(msg):
    ERRORS.append(msg)
    print(f"  FAIL  {msg}")


def warn(msg):
    WARNINGS.append(msg)
    print(f"  WARN  {msg}")


def load(source, table):
    p = DATASETS / source / f"{table}.csv"
    if not p.exists():
        fail(f"Missing file: {p.relative_to(DATASETS.parent.parent)}")
        return None
    return pd.read_csv(p, low_memory=False)


# ── Load all tables ──────────────────────────────────────────────────────────
print("\n[1] Loading tables...")
products         = load("shopify", "products")
variants         = load("shopify", "product_variants")
inv_items        = load("shopify", "inventory_items")
inv_levels       = load("shopify", "inventory_levels")
locations        = load("shopify", "locations")
customers        = load("shopify", "customers")
orders           = load("shopify", "orders")
line_items       = load("shopify", "order_line_items")
refunds          = load("shopify", "refunds")
transactions     = load("shopify", "transactions")
inv_snapshots    = load("bronze_pre_aggregated", "inventory_snapshots")
sc_charges       = load("stripe", "charges")
sc_refunds       = load("stripe", "refunds")
sc_disputes      = load("stripe", "disputes")
sc_pmethods      = load("stripe", "payment_methods")
sc_customers     = load("stripe", "customers")
ga4_events       = load("ga4", "events")
ga4_users        = load("ga4", "users")
kl_profiles      = load("klaviyo", "profiles")
kl_events        = load("klaviyo", "events")
kl_campaigns     = load("klaviyo", "campaigns")
kl_flows         = load("klaviyo", "flows")
meta_insights    = load("meta_ads", "daily_insights")
meta_campaigns   = load("meta_ads", "campaigns")
meta_ad_sets     = load("meta_ads", "ad_sets")
meta_ads         = load("meta_ads", "ads")

# Abort if critical tables are missing
critical = [products, variants, inv_items, customers, orders, line_items,
            sc_charges, kl_profiles, ga4_events, meta_insights]
if any(t is None for t in critical):
    print("\nCritical tables missing — aborting QA.")
    sys.exit(1)

ok(f"All tables loaded — orders={len(orders):,}, line_items={len(line_items):,}, "
   f"customers={len(customers):,}, variants={len(variants):,}")


# ── 2. Null checks on PKs / FKs ──────────────────────────────────────────────
print("\n[2] Null checks...")

def check_no_nulls(df, col, label):
    if df is None:
        return
    n = df[col].isna().sum()
    if n == 0:
        ok(f"{label}.{col} has no nulls")
    else:
        fail(f"{label}.{col} has {n} nulls")

check_no_nulls(products,      "id",                 "products")
check_no_nulls(variants,      "id",                 "variants")
check_no_nulls(variants,      "product_id",         "variants")
check_no_nulls(variants,      "inventory_item_id",  "variants")
check_no_nulls(inv_items,     "id",                 "inventory_items")
check_no_nulls(customers,     "id",                 "customers")
check_no_nulls(customers,     "email",              "customers")
check_no_nulls(orders,        "id",                 "orders")
check_no_nulls(orders,        "customer_id",        "orders")
check_no_nulls(line_items,    "id",                 "line_items")
check_no_nulls(line_items,    "order_id",           "line_items")
check_no_nulls(line_items,    "variant_id",         "line_items")
check_no_nulls(sc_charges,    "id",                 "stripe_charges")
check_no_nulls(sc_charges,    "id",                 "stripe_charges")
check_no_nulls(kl_profiles,   "id",                 "klaviyo_profiles")
check_no_nulls(ga4_events,    "event_name",         "ga4_events")
check_no_nulls(meta_insights, "date_start",         "meta_insights")
check_no_nulls(meta_insights, "campaign_id",        "meta_insights")


# ── 3. Uniqueness ────────────────────────────────────────────────────────────
print("\n[3] Uniqueness checks...")

def check_unique(df, col, label):
    if df is None:
        return
    dupes = df[col].duplicated().sum()
    if dupes == 0:
        ok(f"{label}.{col} is unique")
    else:
        fail(f"{label}.{col} has {dupes} duplicates")

check_unique(products,     "id",    "products")
check_unique(variants,     "id",    "variants")
check_unique(inv_items,    "id",    "inventory_items")
check_unique(customers,    "id",    "customers")
check_unique(customers,    "email", "customers")
check_unique(orders,       "id",    "orders")
check_unique(line_items,   "id",    "line_items")
check_unique(sc_charges,   "id",    "stripe_charges")
check_unique(sc_customers, "id",    "stripe_customers")
check_unique(kl_profiles,  "id",    "klaviyo_profiles")


# ── 4. Referential integrity ──────────────────────────────────────────────────
print("\n[4] Referential integrity...")

def check_fk(child_df, child_col, parent_df, parent_col, label):
    if child_df is None or parent_df is None:
        return
    child_vals  = set(child_df[child_col].dropna().astype(str))
    parent_vals = set(parent_df[parent_col].dropna().astype(str))
    orphans = child_vals - parent_vals
    if not orphans:
        ok(f"{label}: all {len(child_vals)} values match parent")
    else:
        fail(f"{label}: {len(orphans)} orphan value(s): {list(orphans)[:5]}")

check_fk(variants,    "product_id",        products,  "id",  "variants.product_id -> products.id")
check_fk(variants,    "inventory_item_id", inv_items, "id",  "variants.inventory_item_id -> inventory_items.id")
check_fk(line_items,  "order_id",          orders,    "id",  "line_items.order_id -> orders.id")
check_fk(line_items,  "variant_id",        variants,  "id",  "line_items.variant_id -> variants.id")
check_fk(refunds,     "order_id",          orders,    "id",  "refunds.order_id -> orders.id") if refunds is not None else None
check_fk(transactions,"order_id",          orders,    "id",  "transactions.order_id -> orders.id") if transactions is not None else None

# Meta Ads hierarchy
check_fk(meta_ad_sets, "campaign_id", meta_campaigns, "id", "meta_ad_sets.campaign_id -> meta_campaigns.id")
check_fk(meta_ads,     "adset_id",    meta_ad_sets,   "id", "meta_ads.adset_id -> meta_ad_sets.id")
check_fk(meta_insights,"campaign_id", meta_campaigns, "id", "meta_insights.campaign_id -> meta_campaigns.id")

# Klaviyo FKs
if kl_events is not None and kl_profiles is not None:
    check_fk(kl_events, "profile_id", kl_profiles, "id", "klaviyo_events.profile_id -> profiles.id")
if kl_events is not None and kl_campaigns is not None:
    kl_campaign_events = kl_events[kl_events["campaign_id"].notna() & (kl_events["campaign_id"] != "")]
    if len(kl_campaign_events) > 0:
        check_fk(kl_campaign_events, "campaign_id", kl_campaigns, "id",
                 "klaviyo_events[campaign].campaign_id -> campaigns.id")
    else:
        ok("klaviyo_events: no campaign events to check FK (ok if all flow events)")
if kl_events is not None and kl_flows is not None:
    kl_flow_events = kl_events[kl_events["flow_id"].notna() & (kl_events["flow_id"] != "")]
    if len(kl_flow_events) > 0:
        check_fk(kl_flow_events, "flow_id", kl_flows, "id",
                 "klaviyo_events[flow].flow_id -> flows.id")
    else:
        ok("klaviyo_events: no flow events to check FK (ok if all campaign events)")


# ── 5. Data type / format validation ─────────────────────────────────────────
print("\n[5] Data type / format validation...")

# Stripe created — should be integer Unix epoch
try:
    epochs = sc_charges["created"].astype(float)
    # Year 2026 in Unix time: roughly 1735686000 to 1767222000
    valid = ((epochs >= 1_700_000_000) & (epochs <= 1_800_000_000)).all()
    if valid:
        ok(f"stripe_charges.created looks like Unix epoch (sample={int(epochs.iloc[0])})")
    else:
        fail(f"stripe_charges.created out of range (sample={epochs.iloc[0]})")
except Exception as e:
    fail(f"stripe_charges.created parse error: {e}")

# GA4 event_timestamp — microseconds since epoch
try:
    ts = ga4_events["event_timestamp"].astype(float)
    # 2026 in microseconds: roughly 1.73e15 to 1.77e15
    valid = ((ts >= 1_700_000_000_000_000) & (ts <= 1_800_000_000_000_000)).all()
    if valid:
        ok(f"ga4_events.event_timestamp looks like microsecond epoch (sample={int(ts.iloc[0])})")
    else:
        fail(f"ga4_events.event_timestamp out of range (sample={ts.iloc[0]})")
except Exception as e:
    fail(f"ga4_events.event_timestamp parse error: {e}")

# GA4 event_date — YYYYMMDD string
try:
    sample = str(ga4_events["event_date"].iloc[0])
    pd.to_datetime(sample, format="%Y%m%d")
    ok(f"ga4_events.event_date is YYYYMMDD format (sample={sample})")
except Exception as e:
    fail(f"ga4_events.event_date format error: {e}")

# JSON parseability: note_attributes, discount_codes
for tbl, col, label in [
    (orders, "note_attributes", "orders.note_attributes"),
    (orders, "discount_codes", "orders.discount_codes"),
]:
    if tbl is None:
        continue
    if col not in tbl.columns:
        warn(f"{label} column not found")
        continue
    sample_vals = tbl[col].dropna().head(20)
    bad = 0
    for v in sample_vals:
        try:
            json.loads(str(v))
        except Exception:
            bad += 1
    if bad == 0:
        ok(f"{label} is valid JSON (checked {len(sample_vals)} rows)")
    else:
        fail(f"{label} has {bad}/20 rows with invalid JSON")

# Meta Ads actions / action_values JSON
for col in ["actions", "action_values"]:
    if col in meta_insights.columns:
        sample_vals = meta_insights[col].dropna().head(20)
        bad = sum(1 for v in sample_vals if not _is_json(v))
        if bad == 0:
            ok(f"meta_insights.{col} is valid JSON (checked {len(sample_vals)} rows)")
        else:
            fail(f"meta_insights.{col} has {bad}/20 invalid JSON rows")


# ── 6. Accepted values ────────────────────────────────────────────────────────
print("\n[6] Accepted values...")

FINANCIAL_STATUSES = {"paid", "pending", "refunded", "partially_paid", "partially_refunded", "voided"}
STRIPE_STATUSES     = {"succeeded", "failed", "pending"}

if orders is not None:
    bad = set(orders["financial_status"].dropna().unique()) - FINANCIAL_STATUSES
    if not bad:
        ok("orders.financial_status all valid")
    else:
        fail(f"orders.financial_status invalid values: {bad}")

if sc_charges is not None:
    bad = set(sc_charges["status"].dropna().unique()) - STRIPE_STATUSES
    if not bad:
        ok("stripe_charges.status all valid")
    else:
        fail(f"stripe_charges.status invalid values: {bad}")


# ── 7. Monetary sanity ────────────────────────────────────────────────────────
print("\n[7] Monetary sanity...")

if orders is not None:
    neg_total = (orders["total_price"].astype(float) < 0).sum()
    zero_total = (orders["total_price"].astype(float) == 0).sum()
    if neg_total == 0:
        ok(f"orders.total_price: no negative values")
    else:
        fail(f"orders.total_price: {neg_total} negative rows")
    if zero_total == 0:
        ok(f"orders.total_price: no zero values")
    else:
        warn(f"orders.total_price: {zero_total} zero values (possible test orders)")

if sc_charges is not None:
    neg = (sc_charges["amount"].astype(float) < 0).sum()
    if neg == 0:
        ok("stripe_charges.amount: no negative values")
    else:
        fail(f"stripe_charges.amount: {neg} negative rows")

if inv_snapshots is not None and "inventory_value" in inv_snapshots.columns:
    neg = (inv_snapshots["inventory_value"].astype(float) < 0).sum()
    if neg == 0:
        ok("inventory_snapshots.inventory_value: no negative values")
    else:
        fail(f"inventory_snapshots.inventory_value: {neg} negative rows")


# ── 8. Customer stats post-update ─────────────────────────────────────────────
print("\n[8] Customer stats...")

if customers is not None and orders is not None:
    # Customers with at least one paid/partially_paid/partially_refunded order
    # should have orders_count >= 1 (Shopify excludes fully refunded/voided orders)
    REVENUE_STATUSES = {"paid", "partially_paid", "partially_refunded"}
    revenue_orders = orders[orders["financial_status"].isin(REVENUE_STATUSES)]
    cust_with_revenue = set(revenue_orders["customer_id"].dropna().astype(int))

    cust_df = customers.copy()
    cust_df["_id_int"] = cust_df["id"].astype(int)
    matched = cust_df[cust_df["_id_int"].isin(cust_with_revenue)]

    zero_orders = (matched["orders_count"].astype(int) == 0).sum()
    if zero_orders == 0:
        ok(f"customers with revenue orders all have orders_count >= 1 (n={len(matched):,})")
    else:
        fail(f"{zero_orders} customers have revenue orders but orders_count == 0")

    zero_spend = (matched["total_spent"].astype(float) == 0).sum()
    if zero_spend == 0:
        ok("customers with revenue orders all have total_spent > 0")
    else:
        fail(f"{zero_spend} customers have revenue orders but total_spent == 0")


# ── 9. Story arc verifications ────────────────────────────────────────────────
print("\n[9] Story arc checks...")

if orders is not None:
    orders["order_date"] = pd.to_datetime(orders["created_at"]).dt.date

    # Story 1: BFCM (Nov 28 – Dec 1) — higher order volume
    bfcm_dates = [date(2026, 11, 28), date(2026, 11, 29), date(2026, 11, 30), date(2026, 12, 1)]
    bfcm_orders = orders[orders["order_date"].isin(bfcm_dates)]

    avg_daily = len(orders) / 365
    bfcm_daily_avg = len(bfcm_orders) / 4
    if bfcm_daily_avg >= avg_daily * 2:
        ok(f"Story 1 BFCM: {bfcm_daily_avg:.0f} orders/day vs {avg_daily:.0f} avg "
           f"({bfcm_daily_avg/avg_daily:.1f}x)")
    else:
        fail(f"Story 1 BFCM peak not high enough: {bfcm_daily_avg:.0f} vs {avg_daily:.0f} avg "
             f"({bfcm_daily_avg/avg_daily:.1f}x, expected >= 2x)")

    # Story 1: BFCM discount application rate
    bfcm_with_discount = 0
    for _, row in bfcm_orders.iterrows():
        dc = str(row.get("discount_codes", "[]"))
        try:
            codes = json.loads(dc)
            if codes:
                bfcm_with_discount += 1
        except Exception:
            pass
    if len(bfcm_orders) > 0:
        bfcm_disc_rate = bfcm_with_discount / len(bfcm_orders)
        if bfcm_disc_rate >= 0.80:
            ok(f"Story 1 BFCM discount rate: {bfcm_disc_rate:.1%} (>= 80% threshold)")
        else:
            fail(f"Story 1 BFCM discount rate: {bfcm_disc_rate:.1%} (expected >= 80%)")

    # Story 2: No orders for variant 2000001 during Apr 8–25
    if line_items is not None:
        stockout_dates = pd.date_range("2026-04-08", "2026-04-25").date
        orders_in_stockout = orders[orders["order_date"].isin(stockout_dates)]["id"].astype(str)
        li_in_stockout = line_items[
            line_items["order_id"].astype(str).isin(orders_in_stockout)
        ]
        s2_sales_during_stockout = li_in_stockout[
            li_in_stockout["variant_id"].astype(str) == "2000001"
        ]
        if len(s2_sales_during_stockout) == 0:
            ok("Story 2: no sales of variant 2000001 during Apr 8–25 stockout")
        else:
            fail(f"Story 2: {len(s2_sales_during_stockout)} line items for variant 2000001 "
                 f"during stockout window (should be 0)")

    # Story 4: No orders for variant 2000002 during Sep 22 – Oct 7
    if line_items is not None:
        viral_stockout_dates = pd.date_range("2026-09-22", "2026-10-07").date
        orders_in_viral_so = orders[orders["order_date"].isin(viral_stockout_dates)]["id"].astype(str)
        li_in_viral_so = line_items[
            line_items["order_id"].astype(str).isin(orders_in_viral_so)
        ]
        s4_sales_during_stockout = li_in_viral_so[
            li_in_viral_so["variant_id"].astype(str) == "2000002"
        ]
        if len(s4_sales_during_stockout) == 0:
            ok("Story 4: no sales of variant 2000002 during Sep 22–Oct 7 stockout")
        else:
            fail(f"Story 4: {len(s4_sales_during_stockout)} line items for variant 2000002 "
                 f"during stockout window (should be 0)")

    # Story 4: Viral peak — Sep 14-28 should be significantly above average
    viral_dates = pd.date_range("2026-09-14", "2026-09-28").date
    viral_orders = orders[orders["order_date"].isin(viral_dates)]
    viral_daily_avg = len(viral_orders) / 15
    if viral_daily_avg >= avg_daily * 2:
        ok(f"Story 4 viral peak: {viral_daily_avg:.0f} orders/day vs {avg_daily:.0f} avg "
           f"({viral_daily_avg/avg_daily:.1f}x)")
    else:
        warn(f"Story 4 viral peak modest: {viral_daily_avg:.0f} vs {avg_daily:.0f} avg "
             f"({viral_daily_avg/avg_daily:.1f}x) — small tier has high variance")

# Story 2: Inventory — verify stockout reflected in snapshots
if inv_snapshots is not None:
    snap = inv_snapshots[inv_snapshots["inventory_item_id"].astype(str) == "3000001"]
    if len(snap) > 0:
        snap_stockout = snap[snap["snapshot_date"].isin(
            [d.isoformat() for d in pd.date_range("2026-04-08", "2026-04-25").date]
        )]
        if len(snap_stockout) > 0:
            all_zero = (snap_stockout["available"].astype(int) == 0).all()
            if all_zero:
                ok(f"Story 2: inventory_snapshots shows 0 stock for item 3000001 during Apr 8–25 "
                   f"({len(snap_stockout)} rows)")
            else:
                non_zero = snap_stockout[snap_stockout["available"].astype(int) > 0]
                fail(f"Story 2: {len(non_zero)} snapshot rows show non-zero stock for item 3000001 "
                     f"during Apr 8–25 stockout")
        else:
            warn("Story 2: no snapshot rows found for item 3000001 in Apr 8–25 range")
    else:
        warn("Story 2: inventory_item_id 3000001 not found in snapshots")

# Story 4: Inventory — verify stockout reflected in snapshots
if inv_snapshots is not None:
    snap4 = inv_snapshots[inv_snapshots["inventory_item_id"].astype(str) == "3000002"]
    if len(snap4) > 0:
        snap4_stockout = snap4[snap4["snapshot_date"].isin(
            [d.isoformat() for d in pd.date_range("2026-09-22", "2026-10-07").date]
        )]
        if len(snap4_stockout) > 0:
            all_zero = (snap4_stockout["available"].astype(int) == 0).all()
            if all_zero:
                ok(f"Story 4: inventory_snapshots shows 0 stock for item 3000002 during Sep 22–Oct 7 "
                   f"({len(snap4_stockout)} rows)")
            else:
                non_zero = snap4_stockout[snap4_stockout["available"].astype(int) > 0]
                fail(f"Story 4: {len(non_zero)} snapshot rows show non-zero stock for item 3000002 "
                     f"during Sep 22–Oct 7 stockout")
        else:
            warn("Story 4: no snapshot rows found for item 3000002 in Sep 22–Oct 7 range")
    else:
        warn("Story 4: inventory_item_id 3000002 not found in snapshots")

# Story 5: No resort wear orders before Mar 1, 2026
RESORT_WEAR_SKU_PREFIX = "RW-"
if line_items is not None and variants is not None and orders is not None:
    rw_variants = variants[variants["sku"].astype(str).str.startswith(RESORT_WEAR_SKU_PREFIX)]["id"].astype(str).tolist()
    if rw_variants:
        rw_line_items = line_items[line_items["variant_id"].astype(str).isin(rw_variants)]
        pre_launch_orders = orders[orders["order_date"] < date(2026, 3, 1)]["id"].astype(str)
        rw_pre_launch = rw_line_items[rw_line_items["order_id"].astype(str).isin(pre_launch_orders)]
        if len(rw_pre_launch) == 0:
            ok(f"Story 5: no resort wear orders before Mar 1 "
               f"(rw_variants={len(rw_variants)}, rw_total_li={len(rw_line_items)})")
        else:
            fail(f"Story 5: {len(rw_pre_launch)} resort wear orders before Mar 1 launch")
    else:
        warn("Story 5: no RW- SKU variants found in product_variants — check sku generation")


# ── 10. Summary ───────────────────────────────────────────────────────────────
print(f"\n{'='*60}")
print(f"  PASSED : {PASSED}")
print(f"  FAILED : {len(ERRORS)}")
print(f"  WARNED : {len(WARNINGS)}")
print(f"{'='*60}")

if ERRORS:
    print("\nFAILURES:")
    for e in ERRORS:
        print(f"  - {e}")

if WARNINGS:
    print("\nWARNINGS:")
    for w in WARNINGS:
        print(f"  - {w}")

if not ERRORS:
    print("\nAll checks passed.")
    sys.exit(0)
else:
    sys.exit(1)
