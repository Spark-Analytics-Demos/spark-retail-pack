-- =============================================================================
-- Spark Retail Pack — Resource Monitors (Cost Monitoring)
-- Section 4 Part 3 §4.46 | PHASE_0_CHECKLIST §0.2
--
-- Resource monitors cap credit spend per warehouse per month.
-- Thresholds below are conservative starting points — adjust after a full
-- month of baseline data shows actual consumption patterns.
--
-- Alert emails go to the address on the ACCOUNTADMIN user.
-- Add additional notification emails per your team's on-call setup.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- Account-level monitor — catches runaway spend across all warehouses
-- Suspend all warehouses if monthly account spend hits 500 credits.
-- 500 credits ≈ $500–$1,500 depending on your Snowflake edition/region pricing.
-- Adjust to your contracted monthly credit budget.
-- -----------------------------------------------------------------------------
CREATE RESOURCE MONITOR IF NOT EXISTS RM_ACCOUNT_MONTHLY
    WITH
        CREDIT_QUOTA    = 500
        FREQUENCY       = MONTHLY
        START_TIMESTAMP = IMMEDIATELY
        TRIGGERS
            ON 50  PERCENT DO NOTIFY
            ON 75  PERCENT DO NOTIFY
            ON 90  PERCENT DO NOTIFY
            ON 100 PERCENT DO SUSPEND_IMMEDIATE;

ALTER ACCOUNT SET RESOURCE_MONITOR = RM_ACCOUNT_MONTHLY;

-- -----------------------------------------------------------------------------
-- Per-warehouse monitors — granular cost attribution per workload
-- These keep individual workloads from consuming the entire account budget.
-- -----------------------------------------------------------------------------

-- WH_TRANSFORM — largest expected spend (dbt runs multiple times daily)
CREATE RESOURCE MONITOR IF NOT EXISTS RM_TRANSFORM_MONTHLY
    WITH
        CREDIT_QUOTA    = 200
        FREQUENCY       = MONTHLY
        START_TIMESTAMP = IMMEDIATELY
        TRIGGERS
            ON 75  PERCENT DO NOTIFY
            ON 90  PERCENT DO NOTIFY
            ON 100 PERCENT DO SUSPEND;

ALTER WAREHOUSE WH_TRANSFORM SET RESOURCE_MONITOR = RM_TRANSFORM_MONTHLY;

-- WH_BI — Power BI queries; auto-suspend limits spend but monitor as safety net
CREATE RESOURCE MONITOR IF NOT EXISTS RM_BI_MONTHLY
    WITH
        CREDIT_QUOTA    = 100
        FREQUENCY       = MONTHLY
        START_TIMESTAMP = IMMEDIATELY
        TRIGGERS
            ON 75  PERCENT DO NOTIFY
            ON 100 PERCENT DO SUSPEND;

ALTER WAREHOUSE WH_BI SET RESOURCE_MONITOR = RM_BI_MONTHLY;

-- WH_LOAD — ingestion writes are lightweight; low cap
CREATE RESOURCE MONITOR IF NOT EXISTS RM_LOAD_MONTHLY
    WITH
        CREDIT_QUOTA    = 50
        FREQUENCY       = MONTHLY
        START_TIMESTAMP = IMMEDIATELY
        TRIGGERS
            ON 75  PERCENT DO NOTIFY
            ON 100 PERCENT DO SUSPEND;

ALTER WAREHOUSE WH_LOAD SET RESOURCE_MONITOR = RM_LOAD_MONTHLY;

-- WH_ADHOC — analyst ad-hoc queries; most variable workload
CREATE RESOURCE MONITOR IF NOT EXISTS RM_ADHOC_MONTHLY
    WITH
        CREDIT_QUOTA    = 100
        FREQUENCY       = MONTHLY
        START_TIMESTAMP = IMMEDIATELY
        TRIGGERS
            ON 75  PERCENT DO NOTIFY
            ON 100 PERCENT DO SUSPEND;

ALTER WAREHOUSE WH_ADHOC SET RESOURCE_MONITOR = RM_ADHOC_MONTHLY;

-- -----------------------------------------------------------------------------
-- Verification
-- -----------------------------------------------------------------------------
-- SHOW RESOURCE MONITORS;
