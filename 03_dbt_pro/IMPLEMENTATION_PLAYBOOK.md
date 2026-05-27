# Spark Retail Pack — Implementation Playbook

> **Audience:** Spark Analytics implementation engineers
> **Scope:** Deploying the Spark Retail Pack against a new client's live data
> **Typical engagement:** 4–6 weeks (30 working days)
> **License tier:** Pro — do not share with OSS users or distribute publicly

This document is the step-by-step guide for an implementation engagement. Follow it in sequence. Each section ends with a completion gate — do not proceed until it passes.

---

## Contents

1. [Pre-engagement checklist](#1-pre-engagement-checklist)
2. [Week 1 — Snowflake provisioning and dbt setup](#2-week-1--snowflake-provisioning-and-dbt-setup)
3. [Week 2 — Source connectors and bronze layer](#3-week-2--source-connectors-and-bronze-layer)
4. [Week 3 — dbt build and core validation](#4-week-3--dbt-build-and-core-validation)
5. [Week 4 — KPI validation and semantic layer](#5-week-4--kpi-validation-and-semantic-layer)
6. [Week 5 — Dashboard deployment](#6-week-5--dashboard-deployment)
7. [Week 6 — UAT, training, and handover](#7-week-6--uat-training-and-handover)
8. [Customisation guide](#8-customisation-guide)
9. [Governance configuration](#9-governance-configuration)
10. [Ongoing operations reference](#10-ongoing-operations-reference)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Pre-engagement checklist

Complete every item below before starting Week 1. Missing items cause delays mid-engagement.

### Client-side requirements

- [ ] **Snowflake account** — client has an Enterprise-tier (or higher) Snowflake account in a supported region. Recommended: `AWS_US_WEST_2` or `AWS_EU_WEST_1`. Note the account identifier — it is needed in every `profiles.yml`.
- [ ] **Snowflake admin access** — client can grant `SYSADMIN` and `SECURITYADMIN` privilege to the implementation engineer's user for the duration of setup. This is required to run `setup/snowflake/*.sql`.
- [ ] **Ingestion tool** — client has an active Fivetran or Airbyte instance (or a substitute) capable of connecting to all 5 source systems. Identify the instance URL and an admin-level API token.
- [ ] **Source system credentials** confirmed and shared (via 1Password or equivalent — never email):
  - [ ] Shopify: private app API key with read access to Orders, Customers, Products, Inventory, Transactions
  - [ ] Stripe: restricted API key with read access to Charges, Customers, Refunds, Disputes, PaymentMethods
  - [ ] Google Analytics 4: BigQuery export enabled and BigQuery service account JSON provided (or GA4 Data API credentials for Path 2)
  - [ ] Meta Ads: Meta Business Manager access token with `ads_read` and `business_management` scopes
  - [ ] Klaviyo: private API key with read access to Profiles, Events, Campaigns, Flows
- [ ] **GitHub access** — client repository created (or Spark's private Pro repo forked). Implementation engineer added as maintainer.
- [ ] **Power BI** — client has Power BI Pro or Premium Per User licences for dashboard users. Power BI Desktop installed on the engineer's machine for dashboard deployment.
- [ ] **dbt environment** — Python 3.10+ installed locally. `pip install -r 02_dbt_core/requirements.txt` succeeds.
- [ ] **Reporting decisions locked** (see `PHASE_0_CHECKLIST.md §0.1`):
  - [ ] Reporting currency confirmed (default: USD)
  - [ ] Reporting timezone confirmed (default: Africa/Nairobi EAT UTC+3 — change if needed)
  - [ ] PII handling level confirmed (default: full SHA-256 hash in staging/prod, disabled in dev)

### Spark-side requirements

- [ ] Pro licence signed and countersigned. Start date recorded.
- [ ] Engagement lead assigned. Kickoff meeting scheduled.
- [ ] Access to `03_dbt_pro/` private repo granted to client's implementation contact.
- [ ] Slack channel created for the engagement (format: `#impl-<client-slug>`).
- [ ] Implementation engineer has cloned both `02_dbt_core/` and `03_dbt_pro/` locally.

### Pre-engagement gate

> All items above checked. Kickoff call completed. Client has provided all credentials. Proceed to Week 1.

---

## 2. Week 1 — Snowflake provisioning and dbt setup

**Goal:** Snowflake account is fully provisioned (7 roles, 4 databases, 10 schemas, 4 warehouses, 3 service accounts). dbt connects and parses cleanly. CI/CD pipeline runs.

**Estimated effort:** 3 days implementation engineer + 0.5 days client Snowflake admin

### 2.1 Run Snowflake provisioning scripts

The provisioning scripts are in `setup/snowflake/`. Run them in order as a user with `SYSADMIN` and `SECURITYADMIN` privileges. Each script is idempotent (`CREATE OR REPLACE` / `CREATE IF NOT EXISTS`).

```sql
-- In Snowsight or SnowSQL, run in this exact order:
-- 1. Databases and schemas
\i setup/snowflake/01_databases_and_schemas.sql

-- 2. Virtual warehouses
\i setup/snowflake/02_warehouses.sql

-- 3. Custom roles (7 roles per Section 2.5)
\i setup/snowflake/03_roles.sql

-- 4. Role grants and privilege assignments
\i setup/snowflake/04_grants.sql

-- 5. Service accounts
-- IMPORTANT: Before running, replace all <REPLACE_WITH_STRONG_PASSWORD>
-- placeholders with passwords from your password manager.
\i setup/snowflake/05_service_accounts.sql

-- 6. Resource monitors (cost control per §4.46)
\i setup/snowflake/06_resource_monitors.sql
```

After each script, verify there are no errors in the output. Common issues:
- `GRANT ROLE X TO ROLE Y` failing with a cycle error — see `PHASE_0_CHECKLIST.md §Notes log` for the known resolution.
- Script 04 failing on `FUTURE GRANTS` — ensure you are running as `SECURITYADMIN`.

**Verify provisioning:**

```sql
-- Should show 7 custom roles
SHOW ROLES LIKE 'RETAIL_%';

-- Should show 4 databases
SHOW DATABASES LIKE '%RETAIL%';

-- Should show 4 warehouses
SHOW WAREHOUSES LIKE 'WH_%';

-- Should show 3 service accounts
SHOW USERS LIKE 'SVC_%';
```

### 2.2 Configure dbt credentials

```bash
# Clone the OSS project (if not already cloned)
git clone <client-repo> spark-retail-pack
cd spark-retail-pack/02_dbt_core

# Copy the profiles template
cp profiles.yml.template ~/.dbt/profiles.yml
# OR, for project-local credentials:
cp profiles.yml.template profiles.yml
```

Edit `profiles.yml` and set the following environment variables in a `.env` file (gitignored):

```bash
# .env — never commit this file
SNOWFLAKE_ACCOUNT=<account-identifier>        # e.g. abc12345.us-west-2
SNOWFLAKE_USER=SVC_DBT
SNOWFLAKE_PASSWORD=<svc_dbt_password>
SNOWFLAKE_CI_USER=SVC_DBT
SNOWFLAKE_CI_PASSWORD=<svc_dbt_password>
PII_HASH_SALT=<generate with: python -c "import secrets; print(secrets.token_hex(32))">
```

> **Security:** The PII hash salt must be generated fresh for each client. Never reuse a salt from another engagement. Store it in 1Password under the client's vault, not in any file that touches version control.

```bash
# Validate the connection
cd 02_dbt_core
source ../.env  # or use direnv
dbt debug      # should report "All checks passed"
dbt deps       # install packages
dbt parse      # should complete with 0 errors
```

### 2.3 Set up CI/CD

GitHub Actions workflows are already in `.github/workflows/`. The secrets need to be configured in the client's GitHub repository:

```bash
# Set secrets via GitHub CLI (run from repo root)
gh secret set SNOWFLAKE_ACCOUNT   --body "$SNOWFLAKE_ACCOUNT"
gh secret set SNOWFLAKE_CI_USER   --body "SVC_DBT"
gh secret set SNOWFLAKE_CI_PASSWORD --body "$SNOWFLAKE_CI_PASSWORD"
gh secret set SNOWFLAKE_USER      --body "SVC_DBT"
gh secret set SNOWFLAKE_PASSWORD  --body "$SNOWFLAKE_PASSWORD"
gh secret set PII_HASH_SALT       --body "$PII_HASH_SALT"
```

Push a trivial branch and verify CI passes:

```bash
git checkout -b test/ci-validation
git commit --allow-empty -m "test: verify CI pipeline"
git push -u origin test/ci-validation
# Open the PR — both CI workflows should go green within ~5 minutes
```

Enable branch protection on `main`: Settings → Branches → Add rule for `main`. Require status checks `Lint (SQL + YAML)` and `dbt deps → parse → build`.

### 2.4 Pro project setup

```bash
cd ../03_dbt_pro
dbt deps   # installs 02_dbt_core as a local package dependency
dbt parse  # should complete cleanly
```

### Week 1 gate

> `dbt debug` passes. `dbt parse` passes in both OSS and Pro projects. CI runs green on a test branch. All 7 Snowflake roles exist. All 3 service accounts exist.

---

## 3. Week 2 — Source connectors and bronze layer

**Goal:** All 5 source connectors syncing to `RAW_RETAIL.*`. Initial historical syncs complete. `dbt source freshness` passes.

**Estimated effort:** 3–4 days (connector setup is the most variable part of any engagement — plan for delays on Klaviyo and GA4)

### 3.1 Connector configuration order

Configure connectors in this order. Shopify is the critical path; the others can run in parallel once Shopify is syncing.

| Priority | Connector | Typical sync time | Notes |
|---|---|---|---|
| 1 | Shopify | 2–6 hours | Critical path — blocks staging and dimensions |
| 2 | Stripe | 1–3 hours | Usually fast; parallelize with Shopify |
| 3 | Meta Ads | 1–2 hours | Parallelize |
| 4 | Google Analytics 4 | 3–8 hours | Depends on BigQuery export backfill lag |
| 5 | Klaviyo | 6–24 hours | Heaviest — start this first, let it run overnight |

### 3.2 Fivetran connector setup (standard path)

For each connector in Fivetran:

1. Create a new connector in the Fivetran dashboard.
2. Set the destination schema to match the `RAW_RETAIL` schemas:

   | Source | Destination schema |
   |---|---|
   | Shopify | `RAW_RETAIL.SHOPIFY` |
   | Stripe | `RAW_RETAIL.STRIPE` |
   | Google Analytics 4 | `RAW_RETAIL.GA4` |
   | Meta Ads | `RAW_RETAIL.META_ADS` |
   | Klaviyo | `RAW_RETAIL.KLAVIYO` |

3. Set sync frequency to **1 hour** for Shopify and Stripe; **6 hours** for GA4, Meta Ads, Klaviyo.
4. Run initial historical sync. Do not proceed with dbt until each connector's initial sync reports success.

**For Airbyte:** The destination stream naming follows the same pattern. Use `RAW_RETAIL` as the destination database and the schema names above as stream prefixes.

### 3.3 Table verification

After each connector's initial sync, verify the expected tables exist and have rows:

```sql
-- Shopify
SELECT table_name, row_count
FROM RAW_RETAIL.information_schema.tables
WHERE table_schema = 'SHOPIFY'
ORDER BY table_name;

-- Expected tables: CUSTOMERS, ORDERS, ORDER_LINE_ITEMS, REFUNDS, PRODUCTS,
-- PRODUCT_VARIANTS, INVENTORY_LEVELS, INVENTORY_ITEMS, LOCATIONS, TRANSACTIONS
```

Run the same check for STRIPE, GA4, META_ADS, KLAVIYO. If a table is missing, check the connector's schema mapping in Fivetran/Airbyte.

### 3.4 Source column mapping review

The staging models use `source_col()` macro defaults that match Fivetran's default column naming. If the client uses a different ingestion tool with different column names, update `seeds/source_mappings/` before proceeding.

```bash
# Check for column name mismatches before running dbt
cd 02_dbt_core
dbt build --select tag:staging --target dev --full-refresh
```

If staging models fail with `column not found` errors, inspect the raw table columns in Snowflake and update the relevant `seeds/source_mappings/*.yml` override file.

### 3.5 Source freshness check

```bash
dbt source freshness --target dev
```

All sources should report `Pass`. If any report `Warn` or `Error`, the connector sync is behind — check the Fivetran/Airbyte dashboard for errors.

### Week 2 gate

> All 5 connectors syncing. All expected tables present in `RAW_RETAIL.*`. `dbt source freshness` reports `Pass` for all sources. At least 2 weeks of historical data loaded for Shopify and Stripe.

---

## 4. Week 3 — dbt build and core validation

**Goal:** Full `dbt build` passes. All schema tests green. Core dimensions and facts populated with real client data.

**Estimated effort:** 4 days (plan for 1 extra day of data-quality investigation)

### 4.1 First full build

```bash
cd 02_dbt_core

# Dev build — targets ANALYTICS_RETAIL_DEV
dbt build --target dev --full-refresh
```

A first-time full build on medium-sized client data (1–2 years history, 50K+ orders) typically takes 15–40 minutes on `WH_TRANSFORM` (Small). If it takes longer, check for:
- Missing warehouse auto-resume (should be enabled on `WH_TRANSFORM`)
- Excessive row counts in `RAW_RETAIL.GA4.EVENTS` — GA4 events can be very large; check the `stg_ga4__events` model's filter logic

### 4.2 Interpret build output

A successful build reports:
```
Completed successfully
Done. PASS=NNN WARN=0 ERROR=0 SKIP=0 TOTAL=NNN
```

**Expected warnings** (not failures): dbt may warn about missing `unique_combination_of_columns` tests on tables with composite keys — these are informational.

**Common first-build failures and resolutions:**

| Error | Likely cause | Resolution |
|---|---|---|
| `column "X" does not exist` in a staging model | Ingestion tool uses different column name | Update `seeds/source_mappings/` override |
| `division by zero` in intermediate models | Client has zero-value orders (test/cancelled) | Add filter `WHERE total_price > 0` in `int_orders_enriched.sql` — raise as candidate ADR |
| `unique constraint` test failure on `dim_customer` | Duplicate emails across Shopify and Stripe | Normal for identity resolution — review `int_customer_identity_resolution.sql` match thresholds |
| `relationship` test failure on `fact_orders` | Orders reference deleted customers | Add `LEFT JOIN` fallback to unknown customer in `fact_orders.sql` |

For any failure that requires changing model SQL, create a branch, make the change, and run CI before merging.

### 4.3 Validate staging models

> **Schema naming note:** In dev, dbt prefixes schemas with your developer name (e.g., `dev_alice_staging`, `dev_alice_gold`). The queries below use staging-environment schema names where schemas are clean (`STAGING`, `GOLD`, etc.). Run them against `ANALYTICS_RETAIL_STAGING` after the first staging build, or substitute your personal dev schema prefix.

Run a quick sanity check on the most critical staging models:

```sql
-- Shopify orders: should match order count in Shopify admin
SELECT COUNT(*) FROM ANALYTICS_RETAIL_STAGING.STAGING.STG_SHOPIFY__ORDERS;

-- Date range should match the client's store lifetime
SELECT MIN(created_at), MAX(created_at) FROM ANALYTICS_RETAIL_STAGING.STAGING.STG_SHOPIFY__ORDERS;

-- No orphaned line items
SELECT COUNT(*) FROM ANALYTICS_RETAIL_STAGING.STAGING.STG_SHOPIFY__ORDER_LINE_ITEMS li
LEFT JOIN ANALYTICS_RETAIL_STAGING.STAGING.STG_SHOPIFY__ORDERS o ON li.order_id = o.id
WHERE o.id IS NULL;
-- Expected: 0
```

### 4.4 Validate core dimensions

```sql
-- dim_customer: row count should be close to Shopify customer count
SELECT COUNT(*) FROM ANALYTICS_RETAIL_STAGING.GOLD.DIM_CUSTOMER;

-- No nulls on PK
SELECT COUNT(*) FROM ANALYTICS_RETAIL_STAGING.GOLD.DIM_CUSTOMER WHERE customer_sk IS NULL;
-- Expected: 0

-- dim_product: variant-level granularity
SELECT COUNT(*) FROM ANALYTICS_RETAIL_STAGING.GOLD.DIM_PRODUCT;

-- dim_date: should cover at least 3 years (historical + 1 year forward)
SELECT MIN(date_day), MAX(date_day) FROM ANALYTICS_RETAIL_STAGING.GOLD.DIM_DATE;
```

### 4.5 Validate fact tables

```sql
-- fact_orders: GMV should be in the ballpark of the client's reported revenue
-- mart_sales grain: one row per (order_date × channel × geography)
SELECT
    DATE_TRUNC('month', order_date) AS month,
    SUM(order_count)                AS order_count,
    SUM(gmv)                        AS gmv
FROM ANALYTICS_RETAIL_STAGING.MART_SALES.MART_SALES
GROUP BY 1
ORDER BY 1 DESC
LIMIT 12;

-- Cross-check with Shopify admin's revenue report for the same period.
-- Expect ±5% variance (timing differences, currency rounding).
-- Variance > 10% requires investigation.

-- fact_inventory_snapshot: daily rows per variant
SELECT snapshot_date, COUNT(*) as sku_count
FROM ANALYTICS_RETAIL_STAGING.GOLD.FACT_INVENTORY_SNAPSHOT
GROUP BY 1
ORDER BY 1 DESC
LIMIT 7;
```

### 4.6 PII verification

Verify PII masking is working correctly in dev (disabled) and staging (enabled):

```sql
-- In DEV: emails should be readable (masking disabled)
-- Replace dev_alice_gold with your personal dev schema
SELECT email FROM ANALYTICS_RETAIL_DEV.dev_alice_gold.DIM_CUSTOMER LIMIT 5;

-- In STAGING: emails should be hashed
SELECT email FROM ANALYTICS_RETAIL_STAGING.GOLD.DIM_CUSTOMER LIMIT 5;
-- Expected: 64-character hex strings like "a3f2b1c4..."
```

If staging shows unhashed emails, check that `PII_HASH_SALT` is set correctly in the staging environment's env vars or GitHub Secrets.

### Week 3 gate

> `dbt build` passes with 0 errors in dev. All schema tests green. GMV variance vs. Shopify admin < 10%. PII masking verified correct in staging.

---

## 5. Week 4 — KPI validation and semantic layer

**Goal:** All 25 KPIs return correct values in mart tables. Semantic layer (`03_dbt_pro`) builds cleanly.

**Estimated effort:** 3 days

### 5.1 Build the Pro project

```bash
cd 03_dbt_pro
dbt build --target dev
```

The Pro project depends on `02_dbt_core` as a local package. It adds:
- `mart_pro_sales.sql` — Refund Rate, Return Rate, Revenue by Channel
- `mart_pro_returns.sql` — Return Rate detail
- `mart_pro_customer_ltv.sql` — Customer LTV, Avg Time Between Orders
- `mart_pro_customer_behavior.sql` — CAC by Channel
- `mart_pro_email_engagement.sql` — Email Engagement Rate, ROAS
- `mart_pro_inventory.sql` — Inventory Turnover, Sell-Through Rate, Slow-Moving SKU Count

### 5.2 KPI spot-checks

Validate each KPI against a source the client can independently verify (Shopify analytics, Stripe dashboard, Meta Ads reporting):

**Sales KPIs:**

```sql
-- GMV (KPI 1) — should match Shopify "Total sales" for the same period
-- mart_sales grain: (order_date × channel × geography); SUM to get monthly total
SELECT SUM(gmv) FROM ANALYTICS_RETAIL_STAGING.MART_SALES.MART_SALES
WHERE DATE_TRUNC('month', order_date) = '2025-01-01';

-- AOV (KPI 4) — total GMV / total order_count for the period
SELECT SUM(gmv) / NULLIF(SUM(order_count), 0) AS aov
FROM ANALYTICS_RETAIL_STAGING.MART_SALES.MART_SALES
WHERE DATE_TRUNC('month', order_date) = '2025-01-01';

-- Refund Rate (KPI 6, Pro) — cross-check with Stripe refund dashboard
SELECT refund_rate FROM ANALYTICS_RETAIL_STAGING.MART_SALES.MART_PRO_SALES
WHERE DATE_TRUNC('month', order_date) = '2025-01-01';
```

**Customer KPIs:**

```sql
-- Active Customers (KPI 10/11) — point-in-time: use a single snapshot_date
-- Do NOT SUM across dates — these counts are non-additive
SELECT active_customers_30d, active_customers_90d
FROM ANALYTICS_RETAIL_STAGING.MART_CUSTOMER.MART_CUSTOMER
WHERE snapshot_date = CURRENT_DATE() - 1;

-- New Customers (KPI 12) — in mart_sales, aggregated by order_date
SELECT SUM(new_customers) FROM ANALYTICS_RETAIL_STAGING.MART_SALES.MART_SALES
WHERE DATE_TRUNC('month', order_date) = '2025-01-01';
```

**Inventory KPIs:**

```sql
-- Stockout Rate (KPI 23) — computed in Power BI / semantic layer, not pre-aggregated
-- To spot-check: count SKU-days where is_out_of_stock = TRUE vs. total SKU-days
SELECT
    DATE_TRUNC('month', snapshot_date) AS month,
    SUM(is_out_of_stock::INT)::FLOAT / COUNT(*) AS stockout_rate
FROM ANALYTICS_RETAIL_STAGING.MART_INVENTORY.MART_INVENTORY
GROUP BY 1
ORDER BY 1 DESC
LIMIT 6;
```

Acceptable variance from the client's source system:
- GMV: ±5% (currency timing, partial refund treatment)
- Order counts: ±2% (test orders, cancellations)
- Customer counts: ±3% (identity resolution merging)

Variances outside these bands require root-cause investigation before proceeding to dashboards.

### 5.3 Semantic layer validation

The MetricFlow YAML definitions are in `03_dbt_pro/models/semantic/`. Validate that metric queries return correct results:

```bash
# If using dbt Cloud (Path 1 per ADR-004):
dbt sl query --metrics gmv --group-by metric_time__month --limit 12

# If using dbt Core + materialized views (Path 2 per ADR-004):
# Query the ANALYTICS_RETAIL_DEV.SEMANTIC.* views directly in Snowsight
SELECT * FROM ANALYTICS_RETAIL_DEV.SEMANTIC.METRIC_GMV ORDER BY period DESC LIMIT 12;
```

Cross-check the semantic layer output against the mart table output from §5.2. They should match exactly.

### 5.4 Promote to staging

Once dev validation passes:

```bash
cd 02_dbt_core
dbt build --target staging --full-refresh

cd ../03_dbt_pro
dbt build --target staging
```

Staging uses PII masking. Verify the staging build is clean before touching dashboards.

### Week 4 gate

> Pro project builds cleanly. All 25 KPI values cross-checked against source systems within acceptable variance. Semantic layer queries return correct values. Staging build passes.

---

## 6. Week 5 — Dashboard deployment

**Goal:** All 3 Power BI dashboards connected to the client's Snowflake semantic layer and displaying real data.

**Estimated effort:** 4–5 days

> **Note:** This phase requires Power BI Desktop. Dashboards are `.pbix` files in `04_dashboards/`. They are not editable via CLI.

### 6.1 Power BI connection setup

1. Open Power BI Desktop.
2. For each dashboard file (`Executive_Summary.pbix`, `Customer_360.pbix`, `Inventory_Health.pbix`):
   - File → Open → select the `.pbix`
   - Transform Data → Data Source Settings → Change Source
   - Set the Snowflake server to `<account-identifier>.snowflakecomputing.com`
   - Set the warehouse to `WH_BI`
   - Set the database to `ANALYTICS_RETAIL` (production) or `ANALYTICS_RETAIL_STAGING` (for review)
   - Set the schema to `SEMANTIC` (Path 2) or leave blank for dbt Cloud semantic connector (Path 1)
   - Authenticate using the `SVC_POWERBI` service account credentials

3. Click **Refresh** and verify all visuals populate without errors.

### 6.2 Theming

The pack default theme (`SparkDefault.json`) is in `04_dashboards/themes/`. To apply the client's brand:

1. Use the client brand theme template (`client_brand_template.json`) as a starting point.
2. Update `primaryColor`, `secondaryColor`, `fontFamily` to match the client's brand guide.
3. Save as `<client-slug>_theme.json`.
4. In Power BI Desktop: View → Themes → Browse for themes → select the new file.

For most engagements, the default Spark theme is used for the first go-live and rebranding is done in a subsequent sprint.

### 6.3 Dashboard-specific configuration

**Executive Summary:**
- Verify the date slicer defaults to the last 13 months
- Verify the currency toggle shows USD (or the client's reporting currency)
- Verify the BFCM/peak period annotations appear on the revenue trend chart
- KPI cards should show current month vs. prior month with direction arrows

**Customer 360:**
- Verify customer segment definitions match the client's existing segmentation (or document the pack's definitions for training)
- Verify the cohort retention heatmap renders — this is the heaviest visual; if it times out, check `WH_BI` warehouse size (may need to upsize to Small)

**Inventory Health:**
- Verify the stockout heatmap shows the correct SKU hierarchy (Category → Subcategory → SKU)
- Days of supply thresholds (< 7 days = red, 7–30 = yellow, > 30 = green) — confirm with the client's ops team

### 6.4 Performance validation

Per Section 10.10, dashboards must meet these budgets:

| Metric | Budget | How to measure |
|---|---|---|
| Initial page load | < 5 seconds | Performance Analyser in Power BI Desktop |
| Slicer response | < 2 seconds | Performance Analyser |
| Drill-through response | < 3 seconds | Performance Analyser |

Open Performance Analyser (View → Performance Analyser → Start recording → Refresh visuals). Any visual exceeding its budget needs optimisation — usually either a missing `CLUSTER BY` on the Snowflake table or an overly complex DAX measure.

Common fixes:
- Slow inventory heatmap → add `CLUSTER BY snapshot_date` to `FACT_INVENTORY_SNAPSHOT`
- Slow cohort retention → the `MART_PRO_CUSTOMER_LTV` mart is pre-aggregated; verify it's a table, not a view

### 6.5 Publish to Power BI Service

1. Publish each dashboard to the client's Power BI workspace.
2. Configure scheduled refresh: Settings → Datasets → Scheduled Refresh → Add the Snowflake data source credentials (use `SVC_POWERBI`).
3. Set refresh frequency to match the client's agreed SLA (typically daily at 6:00 AM local time for executive dashboards).
4. Share the workspace with the client's dashboard users (assign `Viewer` role).

### Week 5 gate

> All 3 dashboards load with real data. All performance budgets met. Scheduled refresh configured and tested (run at least one manual refresh). Client stakeholders have access.

---

## 7. Week 6 — UAT, training, and handover

**Goal:** Client signs off on data accuracy. Key users trained. Handover documentation complete.

**Estimated effort:** 3 days

### 7.1 User acceptance testing

Prepare a UAT checklist with the client's analytics lead. For each KPI that the client currently tracks elsewhere (e.g., in a spreadsheet, a legacy BI tool, Shopify analytics):

| KPI | Expected value (client source) | Pack value | Variance | Status |
|---|---|---|---|---|
| Monthly GMV (last full month) | | | | |
| Order count (last full month) | | | | |
| New customers (last full month) | | | | |
| AOV (last 90 days) | | | | |
| Repeat purchase rate (last 12 months) | | | | |
| Total inventory value (current) | | | | |

Document any discrepancies and resolve them before sign-off. Common legitimate differences:
- **GMV variance < 5%**: usually timing (Shopify counts orders on creation date; pack counts on payment date)
- **Customer count variance**: identity resolution merges customers that Shopify treats as separate (same email, different IDs)
- **Inventory value variance**: pack uses `inventory_items.cost`; client may use a different cost basis

Variances that cannot be explained within 1 business day should be escalated to the engagement lead.

### 7.2 Training sessions

Run two sessions. Keep them short and hands-on.

**Session 1 — Dashboard users (1 hour)**
- Overview of the three dashboards and their intended audience
- How to use slicers, drill-through, and export to Excel
- How to interpret KPI cards and direction arrows
- What the data is NOT (not real-time, not transaction-level in dashboards)
- How to request support (Slack channel, SLA)

**Session 2 — Analytics team (2 hours)**
- dbt project structure and how to make changes
- How to run `dbt build` locally and in CI
- How to add a new column to a staging model (walk through a live example)
- How to read the dbt docs site
- Governance: what PII masking means, how the erasure macro works
- How to interpret `dbt source freshness` and respond to freshness failures

Provide the client with a recording of both sessions.

### 7.3 Handover documentation

Complete and hand over the following for each engagement:

1. **`DEPLOYMENT_NOTES.md`** (create in the client repo root) — captures all client-specific decisions made during the engagement:
   - Reporting currency and timezone
   - PII salt location (which secrets manager vault)
   - Custom column overrides made in `seeds/source_mappings/`
   - Any model SQL changes and the reason for each
   - Non-standard connector configuration decisions

2. **Credentials inventory** — a 1Password vault entry named `Spark Retail Pack — <Client Name>` with:
   - `SNOWFLAKE_ACCOUNT`
   - `SVC_DBT` password
   - `SVC_INGEST` password
   - `SVC_POWERBI` password
   - `PII_HASH_SALT`
   - Fivetran/Airbyte API key

3. **Access matrix review** — confirm `06_governance/access_matrix.md` reflects the actual role assignments made during provisioning. Update any rows that were changed.

4. **Post-engagement checklist** — confirm with the client:
   - [ ] Dashboard users have access and can log in
   - [ ] Scheduled refresh is running (check Power BI Service → Datasets → Refresh History)
   - [ ] `dbt source freshness` is running on schedule (check CI deploy workflow logs)
   - [ ] Client's analytics lead knows how to run `dbt build` if needed
   - [ ] Escalation path documented (Slack channel, email, on-call)

### 7.4 Go-live sign-off

Obtain written sign-off from the client's project sponsor confirming:
- Data is accurate to the agreed tolerance
- Dashboards meet performance budgets
- Training has been delivered
- The engagement is complete and the client accepts the delivery

This sign-off triggers the invoice milestone if applicable.

### Week 6 gate

> UAT checklist complete with all KPIs in tolerance. Two training sessions delivered and recorded. `DEPLOYMENT_NOTES.md` committed to client repo. Written sign-off received.

---

## 8. Customisation guide

### 8.1 Reporting currency

The default is USD. To change:

1. In `02_dbt_core/dbt_project.yml`, update:
   ```yaml
   vars:
     reporting_currency: 'GBP'  # or EUR, CAD, AUD, etc.
   ```

2. Verify FX rates are loaded in `RAW_RETAIL.SHOPIFY.CURRENCIES` or the equivalent source. The `int_fx_rates_daily.sql` model handles currency conversion — review its logic for the new reporting currency.

3. Run `dbt build --full-refresh` to rebuild all monetary columns.

### 8.2 Reporting timezone

The default is `Africa/Nairobi` (EAT, UTC+3). To change:

1. In `02_dbt_core/dbt_project.yml`:
   ```yaml
   vars:
     reporting_timezone: 'America/New_York'
   ```

2. Run `dbt build --full-refresh` — all timestamp columns are converted at staging layer.

3. Update `dim_date` to reflect the new timezone's date boundaries if the client's peak hours cross UTC midnight.

### 8.3 Adding a product category mapping

The pack ships with category maps for standard Shopify product types. If the client uses custom product types:

1. Open `02_dbt_core/seeds/product_category_mapping.csv`.
2. Add rows for each custom product type:
   ```
   shopify_product_type,category,subcategory
   "Custom Outerwear","Outerwear","Jackets"
   ```
3. Run `dbt seed && dbt build --select dim_product+` to rebuild the affected models.

### 8.4 Adding a channel mapping

Marketing channel mapping lives in `02_dbt_core/seeds/source_mappings/channel_mapping.csv`. To add or modify channel attribution:

```csv
utm_source,utm_medium,channel
"newsletter","email","Email"
"google","cpc","Paid Search"
"instagram","social","Paid Social"
```

Run `dbt seed && dbt build --select dim_channel+` after changes.

### 8.5 Adjusting incremental lookback windows

Facts use a lookback pattern to catch late-arriving data (Section 4 Part 3 §4.35). The default is 3 days. For clients with large refund windows or delayed GA4 exports, increase this:

```yaml
# 02_dbt_core/dbt_project.yml
vars:
  incremental_lookback_days: 7  # default is 3
```

Larger lookback windows increase incremental build time. 7 days is sufficient for most clients.

---

## 9. Governance configuration

Review and update these files for each engagement before go-live:

### 9.1 `06_governance/ownership.yml`

Update the `owner_email` and `team` fields to reflect the client's data ownership structure. The default values are Spark Analytics placeholders.

```yaml
# Example update
tables:
  - name: dim_customer
    owner_email: "analytics@client.com"  # update this
    team: "Client Analytics Team"         # update this
```

### 9.2 `06_governance/access_matrix.md`

Fill in the client's actual user-to-role assignments. This becomes the reference document for quarterly access reviews.

### 9.3 `06_governance/pii_inventory.md`

Review the PII inventory against the client's privacy policy. Add any client-specific PII fields that are not in the default inventory.

### 9.4 `06_governance/retention.yml`

Confirm retention horizons with the client's legal or compliance team. The defaults (Section 8.9) are:
- Transaction data: 7 years
- Customer profiles: 3 years post-last-activity
- Session data: 2 years
- Marketing events: 3 years

If a client operates under stricter requirements (e.g., GDPR data minimisation commitments), update these values before go-live.

### 9.5 GDPR/CCPA erasure testing

Before go-live on any client with EU or California customers, test the erasure macro. The `customer_erasure` macro reads from `seeds/erasure_requests.csv` — it is not a Snowflake stored procedure.

```bash
# 1. Add a test row to erasure_requests.csv (use a synthetic ID, never a real one)
# seeds/erasure_requests.csv:
#   customer_id,scope,requested_at
#   test-synthetic-id-00001,full_erasure,2026-01-01

# 2. Reload the seed
dbt seed --select erasure_requests --target dev

# 3. Run the erasure macro
dbt run-operation customer_erasure --target dev

# 4. Verify the test customer's PII fields are nulled in dim_customer
# (replace dev_alice_gold with your personal dev schema)
```

```sql
SELECT customer_sk, email, first_name, last_name
FROM ANALYTICS_RETAIL_DEV.dev_alice_gold.DIM_CUSTOMER
WHERE shopify_customer_id = 'test-synthetic-id-00001';
-- Expected: email, first_name, last_name should be NULL or hashed
```

Remove the test row from `erasure_requests.csv` after testing. Never commit real customer IDs to this file.

---

## 10. Ongoing operations reference

After go-live, the client's analytics team manages day-to-day operations. Provide this reference in the handover.

### Daily checks

```bash
# Check source freshness (run by CI on schedule, or manually)
dbt source freshness --target prod

# Check last night's dbt run completed (in CI logs or dbt Cloud)
# All models should show status: success
```

### Weekly checks

```sql
-- Review lineage and model metadata (written by the lineage_edges on-run-end hook)
SELECT * FROM ANALYTICS_RETAIL.METADATA.LINEAGE_EDGES
WHERE downstream_model = 'fact_orders'
ORDER BY upstream_model;

-- Review Snowflake resource monitor status in Snowsight:
-- Admin → Resource Monitors → check WH_TRANSFORM and WH_BI utilisation
-- Alert if any warehouse is consistently > 80% of its monthly credit limit
```

Check CI deploy workflow logs in GitHub Actions for any failed dbt runs. Navigate to Actions → dbt-deploy → most recent run — all steps should be green.

### Responding to freshness failures

If `dbt source freshness` reports `Error` for a source:

1. Check the Fivetran/Airbyte dashboard for connector errors.
2. If the connector is healthy but data is stale, check if the source system had an outage (Shopify Status, Stripe Status pages).
3. If the issue persists > 4 hours, trigger a manual sync in Fivetran/Airbyte.
4. If the manual sync fails, escalate to Spark Analytics support via the Slack channel.

### Adding a new staging model

When the client's data team wants to extend the pack:

```bash
# 1. Create the model file
touch 02_dbt_core/models/staging/shopify/stg_shopify__new_table.sql

# 2. Add it to sources.yml in the same directory
# 3. Write the model following the existing staging conventions

# 4. Add schema.yml entry with description, columns, and tests

# 5. Build and test
dbt build --select stg_shopify__new_table

# 6. PR → CI → merge
```

### Version upgrades

When a new pack version is released:

1. Review the release notes for breaking changes.
2. Create a branch: `git checkout -b upgrade/pack-v1.x.y`
3. Update package versions in `packages.yml`.
4. Run `dbt deps && dbt build --full-refresh --target staging`.
5. Validate key KPIs haven't changed unexpectedly.
6. Merge and deploy.

Major version upgrades (e.g., v1 → v2) require a separate scoping conversation with Spark Analytics.

---

## 11. Troubleshooting

### dbt build fails with "schema does not exist"

The Snowflake schemas were not created, or the service account lacks access.

```sql
-- Check schemas exist
SHOW SCHEMAS IN DATABASE ANALYTICS_RETAIL_DEV;

-- Re-run grants script if needed
\i setup/snowflake/04_grants.sql
```

### PII columns showing as plaintext in staging

The `PII_HASH_SALT` env var is not set for the staging target.

```bash
echo $PII_HASH_SALT  # should print a 64-char hex string, not empty
# If empty, source your .env and re-run
```

### Power BI scheduled refresh fails with "credentials expired"

The `SVC_POWERBI` Snowflake password was rotated without updating Power BI.

1. In Power BI Service → Settings → Datasets → select the dataset → Data Source Credentials → Edit Credentials.
2. Enter the new `SVC_POWERBI` password.
3. Trigger a manual refresh to confirm.

### Klaviyo events not appearing in `fact_email_engagement`

Klaviyo initial sync is often incomplete on first run due to API rate limits. Check:

```sql
SELECT MIN(datetime), MAX(datetime), COUNT(*)
FROM RAW_RETAIL.KLAVIYO.EVENTS;
```

If the date range is less than 6 months and the client has older data, trigger a historical backfill in Fivetran. This can take 12–24 hours.

### `dbt source freshness` reports `Warn` for GA4 after a long weekend

GA4 via BigQuery export has a known 24–48 hour lag on public holidays. This is expected — suppress the warning for 48 hours and check again.

### Incremental models have duplicate rows

The lookback window is too short — late-arriving records are being inserted twice.

```bash
# Rebuild the affected fact table from scratch
dbt build --select fact_orders --full-refresh --target dev
```

If duplicates persist after a full refresh, there is a genuine uniqueness issue in the source data. Investigate with:

```sql
-- Use staging schema (not dev) for clean schema names
SELECT order_id, COUNT(*) FROM ANALYTICS_RETAIL_STAGING.GOLD.FACT_ORDERS
GROUP BY 1 HAVING COUNT(*) > 1;
```

---

## Appendix: engagement timeline summary

| Week | Key deliverable | Gate |
|---|---|---|
| 1 | Snowflake provisioned, dbt connected, CI green | `dbt debug` passes; CI pipeline green |
| 2 | All 5 connectors syncing to `RAW_RETAIL` | `dbt source freshness` all Pass |
| 3 | Full `dbt build` passes in dev | 0 errors; GMV variance < 10% |
| 4 | All 25 KPIs validated; semantic layer live | Variance within tolerance; staging build passes |
| 5 | All 3 dashboards deployed with real data | Performance budgets met; refresh configured |
| 6 | UAT complete; team trained; handover done | Written client sign-off received |

---

*Spark Retail Pack Implementation Playbook — Pro tier, confidential.*
*Do not distribute to OSS users or publish publicly.*
*For questions during an engagement, contact your Spark Analytics engagement lead.*
