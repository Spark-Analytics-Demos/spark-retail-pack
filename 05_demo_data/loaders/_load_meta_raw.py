"""One-off: reload tier-scaled Meta Ads daily_insights into RAW_RETAIL.META_ADS.
daily_insights is the spend source for fact_marketing_spend (CAC/ROAS); the
campaigns/ad_sets/ads RAW tables don't store budgets, so they don't need reload.
Run with RETAIL_LOADER via WH_LOAD; inline file format + positional COPY."""
import os, warnings
warnings.filterwarnings("ignore")
import snowflake.connector

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
env = {}
for line in open(os.path.join(root, ".env")):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1); env[k.strip()] = v.strip().strip('"').strip("'")

csv_path = os.path.join(root, "05_demo_data", "datasets", "small", "meta_ads",
                        "daily_insights.csv").replace("\\", "/")
INLINE_FMT = ("(TYPE=CSV SKIP_HEADER=1 FIELD_OPTIONALLY_ENCLOSED_BY='\"' "
              "NULL_IF=('','NULL','null') EMPTY_FIELD_AS_NULL=TRUE TRIM_SPACE=TRUE)")

con = snowflake.connector.connect(
    account=env["SNOWFLAKE_ACCOUNT"], user=env["SNOWFLAKE_USER"], password=env["SNOWFLAKE_PASSWORD"],
    role="RETAIL_LOADER", warehouse="WH_LOAD", database="RAW_RETAIL", schema="META_ADS")
c = con.cursor()
def run(sql):
    print(">>", " ".join(sql.split())[:95]); c.execute(sql); return c

run("USE WAREHOUSE WH_LOAD")
run("USE SCHEMA META_ADS")
# CSV order: date_start,campaign_id,ad_set_id,ad_id,spend,impressions,clicks,reach,
#            inline_link_clicks,actions,action_values
run("""CREATE OR REPLACE TABLE daily_insights (
  date_start DATE, campaign_id VARCHAR, ad_set_id VARCHAR, ad_id VARCHAR,
  spend NUMBER(18,6), impressions NUMBER, clicks NUMBER, reach NUMBER,
  inline_link_clicks NUMBER, actions VARCHAR, action_values VARCHAR)""")
run(f"PUT 'file://{csv_path}' @%daily_insights OVERWRITE=TRUE AUTO_COMPRESS=TRUE")
run(f"COPY INTO daily_insights FROM @%daily_insights FILE_FORMAT={INLINE_FMT} ON_ERROR=ABORT_STATEMENT")

print("\n=== verify ===")
c.execute("select count(*), round(sum(spend)) from daily_insights")
print("rows, total_spend:", c.fetchone())
c.close(); con.close(); print("DONE")
