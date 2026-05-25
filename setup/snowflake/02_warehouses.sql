-- =============================================================================
-- Spark Retail Pack — Compute Warehouses
-- Section 2.5 | PHASE_0_CHECKLIST §0.2
--
-- Four warehouses, each owned by a specific workload.
-- All warehouses start at XSmall + auto-suspend 60s to minimise credit spend.
-- WH_TRANSFORM: bump to Small when Phase 1 dbt builds begin (Section 2.10).
--
-- Naming reconciliation:
--   Checklist uses WH_LOAD; Section 2.5 uses WH_LOADING.
--   → WH_LOAD adopted (shorter, consistent with profiles.yml.template pattern).
--   Section 2.5 includes WH_ADHOC (for analysts); checklist omits it.
--   → WH_ADHOC included — RETAIL_ANALYST role needs a warehouse.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Ingestion warehouse — Fivetran / Airbyte writes bronze tables
CREATE WAREHOUSE IF NOT EXISTS WH_LOAD
    WAREHOUSE_SIZE   = 'XSMALL'
    AUTO_SUSPEND     = 60
    AUTO_RESUME      = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Ingestion workload — used by RETAIL_LOADER service account. XSmall: writes are not compute-intensive.';

-- dbt transformation warehouse — all dbt runs (dev, staging, prod, CI)
-- Phase 0: XSmall (no real model workloads yet). Bump to Small once
-- Phase 1 dbt builds run, Medium only if full run exceeds 30 min (Section 2.10).
CREATE WAREHOUSE IF NOT EXISTS WH_TRANSFORM
    WAREHOUSE_SIZE   = 'XSMALL'
    AUTO_SUSPEND     = 60
    AUTO_RESUME      = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'dbt transformation workload. Phase 0: XSmall. Bump to Small for Phase 1+.';

-- Power BI query warehouse — BI tool queries marts and semantic layer
CREATE WAREHOUSE IF NOT EXISTS WH_BI
    WAREHOUSE_SIZE   = 'XSMALL'
    AUTO_RESUME      = TRUE
    AUTO_SUSPEND     = 60
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Power BI query workload — RETAIL_BI_READER service account only.';

-- Ad-hoc analyst warehouse — interactive SQL queries by the analytics team
CREATE WAREHOUSE IF NOT EXISTS WH_ADHOC
    WAREHOUSE_SIZE   = 'XSMALL'
    AUTO_RESUME      = TRUE
    AUTO_SUSPEND     = 60
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Ad-hoc analyst queries — RETAIL_ANALYST role. Separate from BI to avoid contention.';
