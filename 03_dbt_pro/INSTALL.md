# Spark Retail Pack Pro — Installation Guide

> **Audience:** Analytics engineers at client organisations deploying the Pro tier
> **Prerequisite:** The OSS core (`02_dbt_core`) must be installed and `dbt build` must pass before installing Pro

---

## Overview

The Pro tier is a separate dbt project that sits on top of the OSS core. It adds:

- MetricFlow semantic layer encoding for all 25 KPIs
- 11 advanced mart models (LTV, CAC, ROAS, sell-through, and more)
- 6 proprietary macros (RFM segmentation, cohort retention, attribution, churn risk, inventory velocity)
- 3 Power BI dashboard packs (Executive Summary, Customer 360, Inventory Health)
- AI-ready metadata (synonyms, example queries, domain facts)

The Pro project references the OSS project as a dependency — it does not duplicate any model code.

---

## Step 1 — Verify OSS core is healthy

Before touching the Pro project, confirm the OSS core is passing:

```bash
cd 02_dbt_core
dbt build
# All models build, all tests pass
```

If any model fails, resolve it before proceeding. The Pro project inherits every dimension and fact from OSS — a failing OSS build will cascade.

---

## Step 2 — Configure Pro credentials

The Pro project uses the same Snowflake connection as OSS but targets the `ANALYTICS_RETAIL` production database by default. Copy the OSS profiles template into the Pro project and update the profile name:

```bash
cp 02_dbt_core/profiles.yml.template 03_dbt_pro/profiles.yml
```

Open `03_dbt_pro/profiles.yml` and change the top-level profile name from `spark_retail_pack` to `spark_retail_pack_pro` — the Pro `dbt_project.yml` declares this name and `dbt build` will fail with a "profile not found" error if they don't match.

Set the target to `prod` (or `staging` if you're validating first). The Pro project expects the same environment variables as OSS:

| Variable | Value |
|---|---|
| `SNOWFLAKE_ACCOUNT` | Your account identifier |
| `SNOWFLAKE_USER` | `SVC_DBT` or your transformer service account |
| `SNOWFLAKE_PASSWORD` | Service account password |
| `SNOWFLAKE_DATABASE` | `ANALYTICS_RETAIL` (prod) or `ANALYTICS_RETAIL_STAGING` |
| `SNOWFLAKE_WAREHOUSE` | `WH_TRANSFORM` |
| `PII_HASH_SALT` | Same salt used in OSS — must match for cross-project hashes to align |

> **Important:** `PII_HASH_SALT` must be identical across OSS and Pro. The Pro tier joins to OSS-produced hashed keys; mismatched salts break every customer join.

---

## Step 3 — Install Pro dependencies

```bash
cd 03_dbt_pro
dbt deps
# Installs the OSS core as a package dependency and resolves transitive deps
```

Verify the OSS project is resolved as a local package:

```bash
ls dbt_packages/spark_retail_pack/
# Should show the OSS project structure
```

---

## Step 4 — Build the Pro layer

```bash
cd 03_dbt_pro
dbt build
# Builds: advanced mart models → semantic layer views → Pro tests
```

Expected build order:
1. Pro advanced mart models (`mart_sales_advanced`, `mart_customer_advanced`, `mart_inventory_advanced`) — these `ref()` OSS models already materialized in Step 1
2. Semantic layer materialized views (`ANALYTICS_RETAIL.SEMANTIC.*`)
3. Pro tests

The OSS models are not re-run by the Pro build — they are referenced as pre-existing tables. This is why Step 1 must pass before Step 4.

Full build time on a fresh Snowflake environment: approximately 15–25 minutes on `WH_TRANSFORM` (Small).

---

## Step 5 — Verify semantic layer views

Confirm the semantic layer views are materialized in Snowflake:

```sql
-- Run in Snowflake Worksheets
SHOW VIEWS IN SCHEMA ANALYTICS_RETAIL.SEMANTIC;
-- Should list 25+ views (one per KPI plus supporting entity views)
```

All 25 KPI views should be present. Pick any metric view from the list and run a `SELECT * ... LIMIT 10` to confirm it returns rows. If a view is missing, check `dbt build --select models/semantic/` for errors and review the model's compilation output.

---

## Step 6 — Connect Power BI

The three `.pbix` files are delivered separately as part of your Pro onboarding package — they are not distributed via the git repository. Your Spark Analytics implementation contact will provide them. Once you have the files, place them in `04_dashboards/` and proceed.

| File | Dashboard |
|---|---|
| `executive_summary.pbix` | Executive Summary (5 pages) |
| `customer_360.pbix` | Customer 360 (5 pages) |
| `inventory_health.pbix` | Inventory Health (5 pages) |

For each dashboard:

1. Open the `.pbix` in **Power BI Desktop**
2. Go to **Transform Data → Data source settings**
3. Replace the demo Snowflake connection with your account details:
   - **Server:** `<your-account>.snowflakecomputing.com`
   - **Warehouse:** `WH_BI`
   - **Database:** `ANALYTICS_RETAIL`
   - **Schema:** `SEMANTIC`
4. Enter the `SVC_POWERBI` service account credentials
5. Click **Refresh** — all 15 pages should populate

If pages show "unable to connect," verify the `RETAIL_BI_READER` role has `SELECT` on `ANALYTICS_RETAIL.SEMANTIC.*` (granted in `setup/snowflake/04_grants.sql`).

---

## Step 7 — Publish to Power BI Service (optional)

To make dashboards available to your organisation:

1. In Power BI Desktop: **File → Publish → Publish to Power BI**
2. Select your workspace
3. Schedule daily refresh via Power BI Service → Dataset → Scheduled Refresh
4. Set refresh credentials to the `SVC_POWERBI` Snowflake account

Recommended refresh schedule: **06:00 local time daily** — after overnight dbt runs complete and before the business day begins.

---

## Step 8 — Validate against demo data (optional but recommended)

Before pointing dashboards at production data, validate against the Northwind Co. demo dataset:

```bash
# Generate medium-tier demo data if not already done
cd 05_demo_data
python generators/main.py --tier medium --seed 42

# Load to your Snowflake bronze layer
cd loaders
snowsql -f load_to_snowflake_bronze.sql

# Run the full OSS + Pro build
cd ../../02_dbt_core && dbt build
cd ../03_dbt_pro && dbt build
```

Then open the Power BI dashboards — you should see Northwind Co. data with all five story arcs visible. Run through the demo scripts in `03_dbt_pro/scenarios/` to confirm each story is readable in the dashboards before switching to client data.

---

## Ongoing operations

### dbt runs

Schedule daily dbt builds via your orchestrator (GitHub Actions, Airflow, dbt Cloud, or Prefect):

```bash
# Recommended daily run order
cd 02_dbt_core && dbt build --target prod
cd ../03_dbt_pro && dbt build --target prod
```

Run the OSS build first; the Pro build will pick up the refreshed OSS models automatically.

### Upgrading

When a new Pro version ships:

1. Pull the latest from the Pro repository
2. Review the release notes for the new version — note any breaking changes or required migration steps
3. Run `dbt deps` to update the OSS package dependency if the OSS version also changed
4. Run `dbt build` — CI tests will catch regressions before they reach production
5. Re-publish updated `.pbix` files to Power BI Service if dashboard files changed

### Erasure requests (GDPR / CCPA)

Add the customer ID to `02_dbt_core/seeds/erasure_requests.csv`, then:

```bash
cd 02_dbt_core
dbt seed --select erasure_requests
dbt run-operation customer_erasure
```

This runs in the OSS project. The Pro marts are rebuilt on the next scheduled `dbt build` and will reflect the erasure automatically.

---

## Support

For implementation and support questions:

- **Email:** [info@sparkanalytics.co.ke](mailto:info@sparkanalytics.co.ke)
- **Implementation issues:** Reference your engagement number in the subject line
- **Bugs in Pro models:** Open a ticket in the Pro GitHub repository

Community questions about the OSS core can be raised in the [public GitHub Issues](https://github.com/Spark-Analytics-Demos/spark-retail-pack/issues).
