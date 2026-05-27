"""
Generate daily inventory snapshots (Shopify inventory_levels) and
inventory movement records from order sales, receipts, and adjustments.

Story 2 and Story 4 inject stockout events on specific SKUs.
Story 5 resort wear line has low sell-through.
"""

import pandas as pd
import numpy as np
from datetime import date, datetime, timedelta, timezone

from stories import story_2_inventory_crisis as s2
from stories import story_4_viral_moment as s4
from stories import story_5_resort_wear_flop as s5


def generate_inventory(
    rng: np.random.Generator,
    cfg: dict,
    products_data: dict,
    orders_data: dict,
    company: dict,
) -> dict:
    """
    Returns dict with DataFrames:
      shopify_inventory_levels  — final snapshot at end of year (for seed/source load)
      inventory_movements       — daily movements (receipts, sales, adjustments)
      daily_snapshots           — daily inventory levels per SKU (for fact_inventory_snapshot)
    """
    variants_df = products_data["product_variants"].copy()
    inv_items_df = products_data["inventory_items"].copy()
    line_items_df = orders_data["shopify_order_line_items"].copy()
    orders_df = orders_data["shopify_orders"].copy()

    location_id = company["shopify"]["locations"][0]["id"]
    start_date = date(2026, 1, 1)
    end_date = date(2026, 12, 31)

    # Build daily sales lookup: variant_id → {date: qty_sold}
    orders_df["order_date"] = pd.to_datetime(orders_df["created_at"]).dt.date
    sales_df = line_items_df.merge(
        orders_df[["id", "order_date", "financial_status"]].rename(columns={"id": "order_id"}),
        on="order_id",
        how="left",
    )
    sales_df = sales_df[sales_df["financial_status"].isin(["paid", "partially_paid", "partially_refunded"])]
    daily_sales = (
        sales_df.groupby(["variant_id", "order_date"])["quantity"].sum().reset_index()
    )
    daily_sales_dict = {}
    for _, row in daily_sales.iterrows():
        vid = int(row["variant_id"])
        d = row["order_date"]
        daily_sales_dict.setdefault(vid, {})[d] = int(row["quantity"])

    # Initial inventory levels (from variants)
    current_stock = {int(row["id"]): int(row["inventory_quantity"])
                     for _, row in variants_df.iterrows()}

    # Map variant_id → inventory_item_id
    variant_to_iid = {int(row["id"]): int(row["inventory_item_id"])
                      for _, row in variants_df.iterrows()}
    # Map inventory_item_id → cost
    iid_to_cost = {int(row["id"]): float(row["cost"])
                   for _, row in inv_items_df.iterrows()}

    snapshot_rows = []
    movement_rows = []
    movement_id = 1

    # Ensure special SKUs have the story-defined initial stock levels.
    # generate_products.py sets inventory_quantity=47 for both, which matches
    # s2.PRE_STOCKOUT_UNITS and s4.PRE_VIRAL_UNITS. Override only if they're
    # somehow absent (shouldn't happen, but defensive).
    if s2.STOCKOUT_VARIANT_ID not in current_stock:
        current_stock[s2.STOCKOUT_VARIANT_ID] = s2.PRE_STOCKOUT_UNITS
    if s4.VIRAL_VARIANT_ID not in current_stock:
        current_stock[s4.VIRAL_VARIANT_ID] = s4.PRE_VIRAL_UNITS

    current_date = start_date
    while current_date <= end_date:
        for vid, stock in list(current_stock.items()):
            # Sales deduction
            sold = daily_sales_dict.get(vid, {}).get(current_date, 0)

            # Story 2: force stockout on HJ-001-MED-BLU
            if vid == s2.STOCKOUT_VARIANT_ID:
                if current_date == s2.STOCKOUT_START:
                    # Drain to 0
                    sold = stock
                elif s2.is_stockout_period(current_date):
                    sold = 0
                elif current_date == s2.RESTOCK_DATE:
                    # Restock event
                    restock_qty = s2.RESTOCK_UNITS
                    movement_rows.append({
                        "id": movement_id,
                        "inventory_item_id": variant_to_iid.get(vid, vid),
                        "location_id": location_id,
                        "happened_at": datetime(current_date.year, current_date.month, current_date.day, 8, 0, 0, tzinfo=timezone.utc).isoformat(),
                        "reason": "receipt",
                        "quantity": restock_qty,
                        "available_adjustment": restock_qty,
                    })
                    movement_id += 1
                    stock += restock_qty
                    current_stock[vid] = stock

            # Story 4: force stockout on Cargo Field Pants
            elif vid == s4.VIRAL_VARIANT_ID:
                if current_date == s4.STOCKOUT_DATE:
                    sold = stock
                elif s4.STOCKOUT_DATE < current_date < s4.RESTOCK_DATE:
                    sold = 0
                elif current_date == s4.RESTOCK_DATE:
                    restock_qty = s4.RESTOCK_UNITS
                    movement_rows.append({
                        "id": movement_id,
                        "inventory_item_id": variant_to_iid.get(vid, vid),
                        "location_id": location_id,
                        "happened_at": datetime(current_date.year, current_date.month, current_date.day, 8, 0, 0, tzinfo=timezone.utc).isoformat(),
                        "reason": "receipt",
                        "quantity": restock_qty,
                        "available_adjustment": restock_qty,
                    })
                    movement_id += 1
                    stock += restock_qty
                    current_stock[vid] = stock

            # Clamp sold to available
            sold = min(sold, stock)

            if sold > 0:
                stock_after = stock - sold
                movement_rows.append({
                    "id": movement_id,
                    "inventory_item_id": variant_to_iid.get(vid, vid),
                    "location_id": location_id,
                    "happened_at": datetime(current_date.year, current_date.month, current_date.day, 23, 0, 0, tzinfo=timezone.utc).isoformat(),
                    "reason": "sale",
                    "quantity": -sold,
                    "available_adjustment": -sold,
                })
                movement_id += 1
                current_stock[vid] = stock_after
                stock = stock_after

            # Weekly restock for non-special SKUs: every Monday, 20% probability
            elif current_date.weekday() == 0 and vid not in (s2.STOCKOUT_VARIANT_ID, s4.VIRAL_VARIANT_ID):
                if stock < 10 or rng.random() < 0.08:
                    restock = int(rng.integers(30, 120))
                    movement_rows.append({
                        "id": movement_id,
                        "inventory_item_id": variant_to_iid.get(vid, vid),
                        "location_id": location_id,
                        "happened_at": datetime(current_date.year, current_date.month, current_date.day, 9, 0, 0, tzinfo=timezone.utc).isoformat(),
                        "reason": "receipt",
                        "quantity": restock,
                        "available_adjustment": restock,
                    })
                    movement_id += 1
                    current_stock[vid] += restock
                    stock = current_stock[vid]

            iid = variant_to_iid.get(vid, vid)
            cost = iid_to_cost.get(iid, 0.0)
            committed = int(rng.integers(0, max(1, stock // 4)))
            inventory_value = round(stock * cost, 2)

            # Slow-mover / overstock flags based on stock relative to daily velocity
            avg_daily_sold = daily_sales_dict.get(vid, {})
            avg_ds = sum(avg_daily_sold.values()) / max(len(avg_daily_sold), 1) if avg_daily_sold else 0.01
            days_of_supply = round(stock / avg_ds, 1) if avg_ds > 0 else 999.0
            is_low_stock = stock <= 10
            is_overstock = days_of_supply > 90 and stock > 50

            snapshot_rows.append({
                "inventory_item_id": iid,
                "location_id": location_id,
                "snapshot_date": current_date.isoformat(),
                "available": stock,
                "quantity_committed": committed,
                "inventory_value": inventory_value,
                "days_of_supply": min(days_of_supply, 999.0),
                "is_low_stock": is_low_stock,
                "is_overstock": is_overstock,
                "updated_at": datetime(current_date.year, current_date.month, current_date.day, 23, 59, 0, tzinfo=timezone.utc).isoformat(),
            })

        current_date += timedelta(days=1)

    # Final inventory levels for Shopify source table
    final_levels = []
    sync_ts = datetime(2026, 12, 31, 23, 59, 0, tzinfo=timezone.utc).isoformat()
    for vid, stock in current_stock.items():
        iid = variant_to_iid.get(vid, vid)
        final_levels.append({
            "inventory_item_id": iid,
            "location_id": location_id,
            "available": max(0, stock),
            "updated_at": sync_ts,
        })

    return {
        "shopify_inventory_levels": pd.DataFrame(final_levels),
        "inventory_movements": pd.DataFrame(movement_rows),
        "daily_snapshots": pd.DataFrame(snapshot_rows),
    }
