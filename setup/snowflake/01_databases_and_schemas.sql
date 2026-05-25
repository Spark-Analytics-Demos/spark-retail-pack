-- =============================================================================
-- Spark Retail Pack — Snowflake Databases & Schemas
-- Section 2.5 | PHASE_0_CHECKLIST §0.2
-- Region: AWS us-west-2 (locked in PHASE_0_DECISIONS.md §4)
--
-- Run order: 01 → 02 → 03 → 04 → 05 → 06
-- Role required: ACCOUNTADMIN
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- DATABASES
-- Four databases: one raw landing zone, three analytics environments.
-- The staging environment (ANALYTICS_RETAIL_STAGING) is the addition over
-- Section 2.5 — added in the checklist to give CI a masking-enabled target
-- that isn't production.
-- -----------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS RAW_RETAIL
    COMMENT = 'Bronze layer — raw landing zone for all ingestion connectors. 1:1 replica of source schemas. No transformation.';

CREATE DATABASE IF NOT EXISTS ANALYTICS_RETAIL
    DATA_RETENTION_TIME_IN_DAYS = 7   -- Section 2.9: 7-day Time Travel on prod
    COMMENT = 'Production analytics database — silver, gold, marts, semantic layer.';

CREATE DATABASE IF NOT EXISTS ANALYTICS_RETAIL_STAGING
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Staging environment — PII masking enabled. CI/CD validation target.';

CREATE DATABASE IF NOT EXISTS ANALYTICS_RETAIL_DEV
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Development sandbox — PII masking disabled (synthetic data only).';

-- -----------------------------------------------------------------------------
-- SCHEMAS — RAW_RETAIL (one per source connector)
-- Ingestion tools (Fivetran/Airbyte) will create tables within these schemas.
-- Pre-creating them lets us apply permissions before connectors are configured.
-- -----------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS RAW_RETAIL.SHOPIFY
    COMMENT = 'Shopify raw tables — Section 6.4';

CREATE SCHEMA IF NOT EXISTS RAW_RETAIL.STRIPE
    COMMENT = 'Stripe raw tables — Section 6.5';

CREATE SCHEMA IF NOT EXISTS RAW_RETAIL.GA4
    COMMENT = 'Google Analytics 4 raw tables — Section 6.6';

CREATE SCHEMA IF NOT EXISTS RAW_RETAIL.META_ADS
    COMMENT = 'Meta Ads raw tables — Section 6.7';

CREATE SCHEMA IF NOT EXISTS RAW_RETAIL.KLAVIYO
    COMMENT = 'Klaviyo raw tables — Section 6.8';

-- -----------------------------------------------------------------------------
-- SCHEMAS — ANALYTICS_RETAIL (production)
-- Schema names match dbt_project.yml +schema settings.
-- Note on naming: checklist uses BRONZE/SILVER/GOLD as layer labels.
-- Actual Snowflake schema names follow the dbt_project.yml convention.
-- -----------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL.STAGING
    COMMENT = 'Silver layer — stg_* models. Cleaned, typed, source-mapped.';

CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL.INTERMEDIATE
    COMMENT = 'Intermediate layer — int_* models (ephemeral in dbt; schema exists for safety).';

CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL.GOLD
    COMMENT = 'Gold layer — dim_* and fact_* canonical models. Source-agnostic.';

CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL.MART_SALES
    COMMENT = 'Sales Analytics mart — pre-joined, pre-aggregated for dashboard consumption.';

CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL.MART_CUSTOMER
    COMMENT = 'Customer 360 mart.';

CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL.MART_INVENTORY
    COMMENT = 'Inventory Health mart.';

CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL.SEMANTIC
    COMMENT = 'Semantic layer — MetricFlow-generated or materialized views (ADR-004 Path 2).';

CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL.METADATA
    COMMENT = 'Audit trail, lineage logs, data quality results — Section 8 / ADR-002.';

CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL.SEEDS
    COMMENT = 'dbt seed tables — source mappings, channel mappings, FX rates, etc.';

CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL.SNAPSHOTS
    COMMENT = 'SCD2 snapshot tables — Section 4 Part 3 §4.34.';

CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL.QUARANTINE
    COMMENT = 'Failed dbt test rows stored for investigation — Section 4 Part 3 §4.37.';

-- -----------------------------------------------------------------------------
-- SCHEMAS — ANALYTICS_RETAIL_STAGING (mirrors production schema set)
-- -----------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_STAGING.STAGING;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_STAGING.INTERMEDIATE;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_STAGING.GOLD;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_STAGING.MART_SALES;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_STAGING.MART_CUSTOMER;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_STAGING.MART_INVENTORY;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_STAGING.SEMANTIC;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_STAGING.METADATA;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_STAGING.SEEDS;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_STAGING.SNAPSHOTS;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_STAGING.QUARANTINE;

-- -----------------------------------------------------------------------------
-- SCHEMAS — ANALYTICS_RETAIL_DEV (mirrors production schema set)
-- Developer personal schemas are created at runtime by dbt via generate_schema_name
-- macro (dev_<username>_<custom_schema>). Only shared schemas below.
-- -----------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_DEV.STAGING;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_DEV.INTERMEDIATE;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_DEV.GOLD;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_DEV.MART_SALES;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_DEV.MART_CUSTOMER;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_DEV.MART_INVENTORY;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_DEV.SEMANTIC;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_DEV.METADATA;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_DEV.SEEDS;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_DEV.SNAPSHOTS;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_RETAIL_DEV.QUARANTINE;
