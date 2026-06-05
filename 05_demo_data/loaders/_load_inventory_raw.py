"""One-off: load regenerated inventory CSVs into RAW_RETAIL.SHOPIFY.
Refreshes inventory_levels (realistic final stock) and creates/loads the daily
inventory_snapshots history. Run with RETAIL_LOADER.

RETAIL_LOADER has CREATE TABLE but NOT CREATE FILE FORMAT on the schema, so we
use an inline file format and positional COPY (table columns are declared in the
exact CSV column order; SKIP_HEADER=1)."""
import os, warnings
warnings.filterwarnings("ignore")
import snowflake.connector

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
env = {}
for line in open(os.path.join(root, ".env")):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1); env[k.strip()] = v.strip().strip('"').strip("'")

ds = os.path.join(root, "05_demo_data", "datasets", "small")
levels_csv = os.path.join(ds, "shopify", "inventory_levels.csv").replace("\\", "/")
snaps_csv  = os.path.join(ds, "bronze_pre_aggregated", "inventory_snapshots.csv").replace("\\", "/")

# Target is configurable (defaults preserve the original RAW_RETAIL/RETAIL_LOADER
# one-off behavior); the smoke test overrides these via env to load an isolated
# RAW_RETAIL_SMOKE as RETAIL_TRANSFORMER on WH_TRANSFORM.
def _cfg(key, default):
    return os.environ.get(key) or env.get(key) or default
DATABASE  = _cfg("SNOWFLAKE_DATABASE", "RAW_RETAIL")
ROLE      = _cfg("SNOWFLAKE_ROLE", "RETAIL_LOADER")
WAREHOUSE = _cfg("SNOWFLAKE_WAREHOUSE", "WH_LOAD")

INLINE_FMT = ("(TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='\"' "
              "NULL_IF=('','NULL','null') EMPTY_FIELD_AS_NULL=TRUE "
              "TRIM_SPACE=TRUE)")

con = snowflake.connector.connect(
    account=env["SNOWFLAKE_ACCOUNT"], user=env["SNOWFLAKE_USER"], password=env["SNOWFLAKE_PASSWORD"],
    role=ROLE, warehouse=WAREHOUSE, database=DATABASE, schema="SHOPIFY")
c = con.cursor()
def run(sql):
    print(">>", " ".join(sql.split())[:95]); c.execute(sql); return c

run(f"USE WAREHOUSE {WAREHOUSE}")
run("USE SCHEMA SHOPIFY")

# --- inventory_levels (refresh). CSV order: inventory_item_id,location_id,available,incoming,updated_at
run("""CREATE OR REPLACE TABLE inventory_levels (
  inventory_item_id NUMBER, location_id VARCHAR, available NUMBER,
  incoming NUMBER, updated_at TIMESTAMP_TZ)""")
run(f"PUT 'file://{levels_csv}' @%inventory_levels OVERWRITE=TRUE AUTO_COMPRESS=TRUE")
run(f"COPY INTO inventory_levels FROM @%inventory_levels FILE_FORMAT={INLINE_FMT} ON_ERROR=ABORT_STATEMENT")

# --- inventory_snapshots (new daily history). CSV order:
# inventory_item_id,location_id,snapshot_date,available,quantity_committed,
# inventory_value,days_of_supply,is_low_stock,is_overstock,updated_at
run("""CREATE OR REPLACE TABLE inventory_snapshots (
  inventory_item_id NUMBER, location_id VARCHAR, snapshot_date DATE,
  available NUMBER, quantity_committed NUMBER, inventory_value NUMBER(18,2),
  days_of_supply NUMBER(18,2), is_low_stock VARCHAR, is_overstock VARCHAR,
  updated_at TIMESTAMP_TZ)""")
run(f"PUT 'file://{snaps_csv}' @%inventory_snapshots OVERWRITE=TRUE AUTO_COMPRESS=TRUE")
run(f"COPY INTO inventory_snapshots FROM @%inventory_snapshots FILE_FORMAT={INLINE_FMT} ON_ERROR=ABORT_STATEMENT")

print("\n=== verify ===")
for t in ["inventory_levels", "inventory_snapshots"]:
    c.execute(f"select count(*) from {t}"); print(t, "rows:", c.fetchone()[0])
c.execute("select min(snapshot_date),max(snapshot_date),count(distinct snapshot_date) from inventory_snapshots")
print("snapshot range (min,max,distinct_days):", c.fetchone())
c.execute("select round(sum(inventory_value)) from inventory_snapshots where snapshot_date='2026-06-15'")
print("total inventory value on 2026-06-15: $", c.fetchone()[0])
c.close(); con.close(); print("DONE")
