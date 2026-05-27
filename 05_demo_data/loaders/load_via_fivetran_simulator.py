"""
Fivetran simulator loader — alternative to load_to_snowflake_bronze.sql.

Mimics how Fivetran lands data into Snowflake by:
  1. Using the Snowflake Python connector
  2. Creating tables with Fivetran-style metadata columns (_fivetran_synced, _fivetran_deleted)
  3. Loading CSVs one chunk at a time (simulates incremental sync)

Requires:
  pip install snowflake-connector-python pandas

Configure via environment variables:
  SNOWFLAKE_ACCOUNT   — your Snowflake account identifier (e.g. RYXGDWD-FPB13834)
  SNOWFLAKE_USER      — Snowflake username
  SNOWFLAKE_PASSWORD  — Snowflake password
  SNOWFLAKE_ROLE      — role to use (default: RETAIL_LOADER)
  SNOWFLAKE_WAREHOUSE — warehouse (default: RETAIL_LOAD_WH)
  SNOWFLAKE_DATABASE  — target database (default: RAW_RETAIL)

Usage:
  python load_via_fivetran_simulator.py --tier small --datasets-dir ../datasets/small
"""

import argparse
import os
import sys
import csv
from pathlib import Path

try:
    import pandas as pd
    import snowflake.connector
    from snowflake.connector.pandas_tools import write_pandas
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Install with: pip install snowflake-connector-python pandas")
    sys.exit(1)

SYNC_TS = "2026-12-31 23:59:00.000 +0000"

# Map source system → Snowflake schema
SOURCE_TO_SCHEMA = {
    "shopify": "SHOPIFY",
    "stripe": "STRIPE",
    "ga4": "GA4",
    "meta_ads": "META_ADS",
    "klaviyo": "KLAVIYO",
}

# Tables that need VARIANT columns (JSON string in CSV → PARSE_JSON on load)
VARIANT_COLUMNS = {
    "shopify/orders": ["discount_codes"],
    "klaviyo/events": ["event_properties"],
    "meta_ads/daily_insights": ["actions", "action_values"],
    "shopify/order_line_items": ["tax_lines", "properties"],
}


def get_connection() -> "snowflake.connector.SnowflakeConnection":
    account = os.environ["SNOWFLAKE_ACCOUNT"]
    user = os.environ["SNOWFLAKE_USER"]
    password = os.environ["SNOWFLAKE_PASSWORD"]
    role = os.environ.get("SNOWFLAKE_ROLE", "RETAIL_LOADER")
    warehouse = os.environ.get("SNOWFLAKE_WAREHOUSE", "RETAIL_LOAD_WH")
    database = os.environ.get("SNOWFLAKE_DATABASE", "RAW_RETAIL")

    return snowflake.connector.connect(
        account=account,
        user=user,
        password=password,
        role=role,
        warehouse=warehouse,
        database=database,
    )


def load_csv_to_snowflake(
    conn,
    csv_path: Path,
    source_system: str,
    table_name: str,
    chunk_size: int = 50_000,
) -> int:
    schema = SOURCE_TO_SCHEMA[source_system]
    full_table = f"{schema}.{table_name.upper()}"
    key = f"{source_system}/{table_name}"

    df = pd.read_csv(csv_path, low_memory=False)

    # Add Fivetran metadata columns
    df["_fivetran_synced"] = SYNC_TS
    df["_fivetran_deleted"] = False

    # Replace NaN with None for correct NULL handling
    df = df.where(pd.notna(df), None)

    total_rows = len(df)
    if total_rows == 0:
        print(f"  {full_table}: 0 rows (skip)")
        return 0

    cur = conn.cursor()

    # Create or replace table (infer schema from DataFrame)
    col_defs = []
    for col in df.columns:
        dtype = str(df[col].dtype)
        variant_cols = VARIANT_COLUMNS.get(key, [])
        if col in variant_cols:
            sf_type = "VARIANT"
        elif "int" in dtype:
            sf_type = "NUMBER"
        elif "float" in dtype:
            sf_type = "FLOAT"
        elif "bool" in dtype:
            sf_type = "BOOLEAN"
        elif col.endswith("_at") or col == "datetime" or col == "_fivetran_synced":
            sf_type = "TIMESTAMP_TZ"
        else:
            sf_type = "VARCHAR"
        col_defs.append(f'"{col.upper()}" {sf_type}')

    create_sql = f"CREATE OR REPLACE TABLE {full_table} ({', '.join(col_defs)})"
    cur.execute(f"USE SCHEMA {schema}")
    cur.execute(create_sql)

    # Load in chunks
    loaded = 0
    for i in range(0, total_rows, chunk_size):
        chunk = df.iloc[i : i + chunk_size].copy()
        # Handle VARIANT columns: write as strings; Snowflake parses them
        success, n_chunks, n_rows, _ = write_pandas(
            conn,
            chunk,
            table_name.upper(),
            schema=schema,
            auto_create_table=False,
            overwrite=False,
            quote_identifiers=False,
        )
        loaded += n_rows
        print(f"  {full_table}: {loaded:,}/{total_rows:,} rows loaded", end="\r")

    print(f"  {full_table}: {loaded:,} rows loaded      ")
    cur.close()
    return loaded


def main():
    parser = argparse.ArgumentParser(description="Load demo data into Snowflake (Fivetran simulator).")
    parser.add_argument("--tier", choices=["small", "medium", "large"], default="small")
    parser.add_argument("--datasets-dir", default=None,
                        help="Path to the datasets/{tier} directory")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print what would be loaded without connecting to Snowflake")
    args = parser.parse_args()

    base_dir = Path(args.datasets_dir) if args.datasets_dir else \
        Path(__file__).parent.parent / "datasets" / args.tier

    if not base_dir.exists():
        print(f"Error: datasets directory not found: {base_dir}")
        print(f"Run: python generators/main.py --tier {args.tier} first")
        sys.exit(1)

    # Discover CSV files
    csv_files = []
    for source_dir in base_dir.iterdir():
        if source_dir.is_dir() and source_dir.name in SOURCE_TO_SCHEMA:
            for csv_path in source_dir.glob("*.csv"):
                table_name = csv_path.stem
                csv_files.append((source_dir.name, table_name, csv_path))

    csv_files.sort()

    if args.dry_run:
        print(f"Dry run — would load {len(csv_files)} tables from {base_dir}:")
        for source, table, path in csv_files:
            row_count = sum(1 for _ in open(path)) - 1
            print(f"  {SOURCE_TO_SCHEMA[source]}.{table.upper():40s} {row_count:>10,} rows")
        return

    print(f"\nConnecting to Snowflake (account: {os.environ.get('SNOWFLAKE_ACCOUNT', '?')})...")
    conn = get_connection()
    print("Connected.\n")

    total_loaded = 0
    for source, table, path in csv_files:
        try:
            n = load_csv_to_snowflake(conn, path, source, table)
            total_loaded += n
        except Exception as e:
            print(f"  ERROR loading {source}/{table}: {e}")
            continue

    conn.close()
    print(f"\nDone. {total_loaded:,} total rows loaded.")


if __name__ == "__main__":
    main()
