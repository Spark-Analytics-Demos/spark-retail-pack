"""
Northwind Co. Demo Data Generator — main orchestrator.

Usage:
  python main.py --tier small             # seed=41, 5K orders
  python main.py --tier medium            # seed=42, 120K orders (default)
  python main.py --tier large             # seed=43, 600K orders
  python main.py --tier medium --seed 99  # override seed (different data, same structure)
  python main.py --tier small --output-dir ../datasets

Per §9.6: same seed → byte-identical output. Default seeds:
  small=41, medium=42, large=43

Output: CSV files in {output_dir}/{tier}/{source_system}/{table}.csv
"""

import argparse
import os
import sys
import time
import yaml
import numpy as np
import pandas as pd
from pathlib import Path

# Ensure generators/ is on the path
sys.path.insert(0, str(Path(__file__).parent))

from generate_products import generate_products
from generate_customers import generate_customers, update_customer_order_stats
from generate_orders import generate_orders
from generate_inventory import generate_inventory
from generate_sessions import generate_sessions
from generate_email_events import generate_email_events
from generate_marketing_spend import generate_marketing_spend

# Tier configurations per §9.4
TIER_CONFIGS = {
    "small": {
        "tier": "small",
        "seed": 41,
        "order_count": 5_000,
        "sku_count": 600,
        "customer_count": 3_500,
    },
    "medium": {
        "tier": "medium",
        "seed": 42,
        "order_count": 120_000,
        "sku_count": 2_400,
        "customer_count": 85_000,
    },
    "large": {
        "tier": "large",
        "seed": 43,
        "order_count": 600_000,
        "sku_count": 2_400,
        "customer_count": 420_000,
    },
}


def load_config(config_dir: Path) -> dict:
    configs = {}
    for name in ["northwind_company", "product_catalog", "customer_segments", "marketing_calendar"]:
        path = config_dir / f"{name}.yml"
        with open(path) as f:
            configs[name] = yaml.safe_load(f)
    return configs


def write_csv(df: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(path, index=False)
    print(f"  wrote {len(df):>10,} rows  ->  {path.relative_to(path.parent.parent.parent)}")


def drop_internal_cols(df: pd.DataFrame) -> pd.DataFrame:
    """Remove columns prefixed with _ before writing (internal use only)."""
    internal = [c for c in df.columns if c.startswith("_")]
    return df.drop(columns=internal)


def main():
    parser = argparse.ArgumentParser(description="Generate Northwind Co. demo data.")
    parser.add_argument(
        "--tier", choices=["small", "medium", "large"], default="medium",
        help="Volume tier (default: medium)",
    )
    parser.add_argument(
        "--seed", type=int, default=None,
        help="Override the default seed for this tier",
    )
    parser.add_argument(
        "--output-dir", default=None,
        help="Output directory (default: ../datasets/{tier})",
    )
    parser.add_argument(
        "--config-dir", default=None,
        help="Config directory (default: ../config)",
    )
    args = parser.parse_args()

    cfg = TIER_CONFIGS[args.tier].copy()
    if args.seed is not None:
        cfg["seed"] = args.seed

    generators_dir = Path(__file__).parent
    root_dir = generators_dir.parent

    config_dir = Path(args.config_dir) if args.config_dir else root_dir / "config"
    output_base = Path(args.output_dir) if args.output_dir else root_dir / "datasets" / args.tier

    print(f"\n=== Northwind Co. Demo Generator ===")
    print(f"  Tier   : {args.tier}")
    print(f"  Seed   : {cfg['seed']}")
    print(f"  Orders : {cfg['order_count']:,}")
    print(f"  SKUs   : {cfg['sku_count']:,}")
    print(f"  Output : {output_base}\n")

    t0 = time.time()

    # Load configs
    print("Loading config files...")
    configs = load_config(config_dir)
    company = configs["northwind_company"]["company"]
    geography = configs["northwind_company"]["geography"]
    company["geography"] = geography
    fx_rates = configs["northwind_company"].get("fx_rates", {})
    catalog = configs["product_catalog"]
    seg_config = configs["customer_segments"]
    marketing_config = configs["marketing_calendar"]

    # Initialize RNG — single seed controls everything per §9.6
    rng = np.random.default_rng(cfg["seed"])
    print(f"RNG initialized with seed {cfg['seed']}")

    # Step 1: Products
    print("\n[1/7] Generating products...")
    products_data = generate_products(rng, cfg, catalog, company)
    write_csv(drop_internal_cols(products_data["products"]),
              output_base / "shopify" / "products.csv")
    write_csv(drop_internal_cols(products_data["product_variants"]),
              output_base / "shopify" / "product_variants.csv")
    write_csv(drop_internal_cols(products_data["inventory_items"]),
              output_base / "shopify" / "inventory_items.csv")
    write_csv(drop_internal_cols(products_data["inventory_levels"]),
              output_base / "shopify" / "inventory_levels.csv")
    write_csv(drop_internal_cols(products_data["locations"]),
              output_base / "shopify" / "locations.csv")

    # Step 2: Customers
    print("\n[2/7] Generating customers...")
    customers_data = generate_customers(rng, cfg, seg_config, company)
    # Don't write shopify_customers yet — orders_count/total_spent updated after orders

    # Step 3: Orders
    print("\n[3/7] Generating orders (this is the slowest step)...")
    orders_data = generate_orders(rng, cfg, products_data,
                                  customers_data["shopify_customers"], seg_config, company)

    # Update customer stats
    updated_customers = update_customer_order_stats(
        customers_data["shopify_customers"],
        orders_data["shopify_orders"],
    )
    customers_data["shopify_customers"] = updated_customers

    write_csv(drop_internal_cols(customers_data["shopify_customers"]),
              output_base / "shopify" / "customers.csv")
    write_csv(drop_internal_cols(orders_data["shopify_orders"]),
              output_base / "shopify" / "orders.csv")
    write_csv(drop_internal_cols(orders_data["shopify_order_line_items"]),
              output_base / "shopify" / "order_line_items.csv")
    write_csv(drop_internal_cols(orders_data["shopify_refunds"]),
              output_base / "shopify" / "refunds.csv")
    write_csv(drop_internal_cols(orders_data["shopify_transactions"]),
              output_base / "shopify" / "transactions.csv")
    write_csv(drop_internal_cols(orders_data["stripe_charges"]),
              output_base / "stripe" / "charges.csv")
    write_csv(drop_internal_cols(orders_data["stripe_refunds"]),
              output_base / "stripe" / "refunds.csv")
    write_csv(drop_internal_cols(orders_data["stripe_disputes"]),
              output_base / "stripe" / "disputes.csv")
    write_csv(drop_internal_cols(orders_data["stripe_payment_methods"]),
              output_base / "stripe" / "payment_methods.csv")
    write_csv(drop_internal_cols(customers_data["stripe_customers"]),
              output_base / "stripe" / "customers.csv")
    write_csv(drop_internal_cols(customers_data["klaviyo_profiles"]),
              output_base / "klaviyo" / "profiles.csv")

    # Step 4: Inventory snapshots
    print("\n[4/7] Generating inventory snapshots...")
    inventory_data = generate_inventory(rng, cfg, products_data, orders_data, company)
    write_csv(drop_internal_cols(inventory_data["shopify_inventory_levels"]),
              output_base / "shopify" / "inventory_levels_final.csv")
    # Daily snapshots are large — write to their own directory
    write_csv(drop_internal_cols(inventory_data["daily_snapshots"]),
              output_base / "bronze_pre_aggregated" / "inventory_snapshots.csv")

    # Step 5: GA4 sessions
    print("\n[5/7] Generating GA4 sessions...")
    sessions_data = generate_sessions(rng, cfg, orders_data)
    write_csv(drop_internal_cols(sessions_data["ga4_events"]),
              output_base / "ga4" / "events.csv")
    write_csv(drop_internal_cols(sessions_data["ga4_users"]),
              output_base / "ga4" / "users.csv")

    # Step 6: Klaviyo email events
    print("\n[6/7] Generating Klaviyo email events...")
    email_data = generate_email_events(rng, cfg, customers_data, marketing_config)
    write_csv(drop_internal_cols(email_data["klaviyo_events"]),
              output_base / "klaviyo" / "events.csv")
    write_csv(drop_internal_cols(email_data["klaviyo_campaigns"]),
              output_base / "klaviyo" / "campaigns.csv")
    write_csv(drop_internal_cols(email_data["klaviyo_flows"]),
              output_base / "klaviyo" / "flows.csv")

    # Step 7: Meta Ads spend
    print("\n[7/7] Generating Meta Ads spend...")
    meta_data = generate_marketing_spend(rng, cfg, marketing_config, company)
    write_csv(drop_internal_cols(meta_data["meta_daily_insights"]),
              output_base / "meta_ads" / "daily_insights.csv")
    write_csv(drop_internal_cols(meta_data["meta_campaigns"]),
              output_base / "meta_ads" / "campaigns.csv")
    write_csv(drop_internal_cols(meta_data["meta_ad_sets"]),
              output_base / "meta_ads" / "ad_sets.csv")
    write_csv(drop_internal_cols(meta_data["meta_ads"]),
              output_base / "meta_ads" / "ads.csv")

    elapsed = time.time() - t0
    ev = orders_data["expected_values"]
    print(f"\n=== Generation complete in {elapsed:.1f}s ===")
    print(f"  Orders generated  : {ev['order_count']:,}")
    print(f"  New customers      : {ev['new_customers']:,}")
    print(f"  GMV (USD)          : ${ev['gmv']:,.2f}")

    # Write expected values snapshot
    _write_expected_values(output_base, cfg, ev, elapsed)


def _write_expected_values(output_base: Path, cfg: dict, ev: dict, elapsed: float) -> None:
    """Write a tier-specific expected_values snapshot alongside the datasets."""
    path = output_base / "expected_values_snapshot.yml"
    content = (
        f"# Auto-generated by main.py — do not edit manually.\n"
        f"# Re-run generator with same seed to reproduce.\n"
        f"tier: {cfg['tier']}\n"
        f"seed: {cfg['seed']}\n"
        f"generation_time_seconds: {elapsed:.1f}\n"
        f"\nmetrics:\n"
        f"  order_count: {ev['order_count']}\n"
        f"  new_customers: {ev['new_customers']}\n"
        f"  gmv_usd: {ev['gmv']:.2f}\n"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    print(f"  wrote expected_values_snapshot  ->  {path.relative_to(path.parent.parent.parent)}")


if __name__ == "__main__":
    main()
