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
  SNOWFLAKE_WAREHOUSE — warehouse (default: WH_LOAD)
  SNOWFLAKE_DATABASE  — target database (default: RAW_RETAIL)

Usage:
  # Initial load — drop and recreate all tables (default)
  python load_via_fivetran_simulator.py --tier small

  # Append new rows to existing tables (does not drop existing data)
  python load_via_fivetran_simulator.py --tier small --mode append

  # Preview what would be loaded without connecting
  python load_via_fivetran_simulator.py --tier small --dry-run
"""

import argparse
import os
import sys
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

# Tables whose JSON-string columns should be typed as VARIANT in Snowflake.
# These are columns containing JSON arrays or objects produced by the generators.
# Even when absent here the staging layer casts to VARIANT, but explicit typing
# at the raw layer avoids silent VARCHAR→VARIANT coercions.
VARIANT_COLUMNS = {
    "shopify/orders":           ["discount_codes"],
    "shopify/refunds":          ["transactions", "refund_line_items"],
    "shopify/order_line_items": ["tax_lines", "properties"],
    "klaviyo/events":           ["event_properties"],
    "meta_ads/daily_insights":  ["actions", "action_values"],
}

# Tables that are considered critical: if any of these fail to load, the
# entire run is aborted rather than continuing with a partial state.
CRITICAL_TABLES = {
    "shopify/orders",
    "shopify/customers",
    "shopify/order_line_items",
    "shopify/refunds",
    "stripe/charges",
}


def get_connection() -> "snowflake.connector.SnowflakeConnection":
    account = os.environ["SNOWFLAKE_ACCOUNT"]
    user = os.environ["SNOWFLAKE_USER"]
    password = os.environ["SNOWFLAKE_PASSWORD"]
    role = os.environ.get("SNOWFLAKE_ROLE", "RETAIL_LOADER")
    warehouse = os.environ.get("SNOWFLAKE_WAREHOUSE", "WH_LOAD")
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
    mode: str = "replace",
    chunk_size: int = 50_000,
) -> int:
    """
    Load a CSV file into Snowflake.

    mode='replace' — DROP + CREATE TABLE then INSERT (default; safe for initial loads).
    mode='append'  — INSERT INTO existing table (no schema changes; assumes table exists).
    """
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
    cur.execute(f"USE SCHEMA {schema}")

    if mode == "replace":
        # Infer Snowflake column types from pandas dtypes
        col_defs = []
        variant_cols = VARIANT_COLUMNS.get(key, [])
        for col in df.columns:
            dtype = str(df[col].dtype)
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
        cur.execute(create_sql)

    # Load in chunks
    loaded = 0
    for i in range(0, total_rows, chunk_size):
        chunk = df.iloc[i : i + chunk_size].copy()
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


def _backdate_snapshot(args) -> None:
    """
    After a fresh replace-mode load, backdate snap_customer.dbt_valid_from to
    each customer's created_at so the fact_orders SCD2 join resolves correctly
    for orders placed before the dbt snapshot was first run.

    Connects to the analytics dev database (ANALYTICS_RETAIL_DEV) using the
    same credentials as the raw loader, but with the RETAIL_TRANSFORMER role.
    No-ops gracefully if the snapshot table doesn't exist yet (pre-first-build).
    """
    analytics_db   = os.environ.get("ANALYTICS_DB", "ANALYTICS_RETAIL_DEV")
    raw_db         = os.environ.get("SNOWFLAKE_DATABASE", "RAW_RETAIL")  # match the bronze load target (smoke isolation)
    analytics_role = "RETAIL_TRANSFORMER"   # always use transformer; loader role has no access
    snap_schema    = "SNAPSHOTS"            # dbt +target_schema: snapshots → Snowflake SNAPSHOTS
    snap_table     = f"{analytics_db}.{snap_schema}.snap_customer"

    try:
        ana_conn = snowflake.connector.connect(
            account=os.environ["SNOWFLAKE_ACCOUNT"],
            user=os.environ["SNOWFLAKE_USER"],
            password=os.environ["SNOWFLAKE_PASSWORD"],
            role=analytics_role,
            warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "WH_TRANSFORM"),
            database=analytics_db,
        )
        cur = ana_conn.cursor()

        # Check table exists before attempting update
        cur.execute(f"SHOW TABLES LIKE 'SNAP_CUSTOMER' IN SCHEMA {analytics_db}.{snap_schema}")
        if not cur.fetchone():
            print(f"\n[snapshot backdate] {snap_table} not found — skipping "
                  f"(run dbt build first, then re-run the loader to backdate).")
            ana_conn.close()
            return

        # Backdate dbt_valid_from to each customer's created_at for the current
        # (dbt_valid_to IS NULL) version. This makes historical orders joinable.
        update_sql = f"""
            UPDATE {snap_table} snap
            SET snap.dbt_valid_from = TO_TIMESTAMP_NTZ(cust.created_at)
            FROM {raw_db}.SHOPIFY.CUSTOMERS cust
            WHERE snap.shopify_customer_id = cust.id::varchar
              AND snap.dbt_valid_to IS NULL
              AND cust.created_at IS NOT NULL
              AND TO_TIMESTAMP_NTZ(cust.created_at) < snap.dbt_valid_from
        """
        cur.execute(update_sql)
        rows_updated = cur.rowcount
        ana_conn.commit()
        ana_conn.close()
        print(f"\n[snapshot backdate] Updated dbt_valid_from for {rows_updated:,} "
              f"customer records in {snap_table}.")
    except Exception as e:
        print(f"\n[snapshot backdate] Skipped ({e}). "
              f"Run dbt build first if the snapshot table doesn't exist yet.")


def main():
    parser = argparse.ArgumentParser(description="Load demo data into Snowflake (Fivetran simulator).")
    parser.add_argument("--tier", choices=["small", "medium", "large"], default="small")
    parser.add_argument("--datasets-dir", default=None,
                        help="Path to the datasets/{tier} directory")
    parser.add_argument("--mode", choices=["replace", "append"], default="replace",
                        help="replace: DROP+CREATE then load (default). "
                             "append: INSERT INTO existing tables without dropping.")
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
        print(f"Dry run — would load {len(csv_files)} tables from {base_dir} (mode={args.mode}):")
        for source, table, path in csv_files:
            row_count = sum(1 for _ in open(path, encoding="utf-8")) - 1
            critical = " [CRITICAL]" if f"{source}/{table}" in CRITICAL_TABLES else ""
            print(f"  {SOURCE_TO_SCHEMA[source]}.{table.upper():40s} {row_count:>10,} rows{critical}")
        return

    print(f"\nConnecting to Snowflake (account: {os.environ.get('SNOWFLAKE_ACCOUNT', '?')}, "
          f"mode={args.mode})...")
    conn = get_connection()
    warehouse = os.environ.get("SNOWFLAKE_WAREHOUSE", "WH_LOAD")
    conn.cursor().execute(f"USE WAREHOUSE {warehouse}")
    print("Connected.\n")

    total_loaded = 0
    errors = []
    for source, table, path in csv_files:
        key = f"{source}/{table}"
        try:
            n = load_csv_to_snowflake(conn, path, source, table, mode=args.mode)
            total_loaded += n
        except Exception as e:
            msg = f"ERROR loading {source}/{table}: {e}"
            print(f"  {msg}")
            errors.append(msg)
            if key in CRITICAL_TABLES:
                print(f"\nAborted: {source}/{table} is a critical table. "
                      f"Fix the error and re-run to avoid partial Snowflake state.")
                conn.close()
                sys.exit(1)
            # Non-critical tables: log and continue
            continue

    conn.close()

    if errors:
        print(f"\nCompleted with {len(errors)} non-critical error(s):")
        for err in errors:
            print(f"  - {err}")
        print(f"\n{total_loaded:,} total rows loaded (partial — see errors above).")
        sys.exit(1)

    print(f"\nDone. {total_loaded:,} total rows loaded.")

    # ── Post-load: backdate snap_customer.dbt_valid_from ──────────────────────
    # On a first-run bulk historical load, dbt snapshot sets dbt_valid_from =
    # current_timestamp() for every record. The fact_orders SCD2 join requires
    # order_timestamp >= dbt_valid_from, so historical orders (before today) get
    # no customer_id match. Fix: set dbt_valid_from = customer created_at so the
    # join works across the full order history. Safe to run after every replace-
    # mode load; has no effect when the snapshot already has correct timestamps.
    if args.mode == "replace":
        _backdate_snapshot(args)


if __name__ == "__main__":
    main()
