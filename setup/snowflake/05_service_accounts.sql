-- =============================================================================
-- Spark Retail Pack — Service Account Users
-- PHASE_0_CHECKLIST §0.2
--
-- Three service accounts: one per integration workload.
-- IMPORTANT: Replace <PLACEHOLDER> values before running.
-- Credentials must be stored in a secrets manager (AWS Secrets Manager,
-- Azure Key Vault, etc.) — never committed to this repo.
--
-- Recommended auth for production: RSA key-pair (not password).
-- profiles.yml.template shows the private_key_path pattern for dbt prod.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- SVC_DBT — dbt transformation service account
-- Used by: dbt runs (local dev via profiles.yml, CI via GitHub Actions)
-- Role: RETAIL_TRANSFORMER
-- -----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS SVC_DBT
    PASSWORD             = '<REPLACE_WITH_STRONG_PASSWORD>'
    DEFAULT_ROLE         = 'RETAIL_TRANSFORMER'
    DEFAULT_WAREHOUSE    = 'WH_TRANSFORM'
    DEFAULT_NAMESPACE    = 'ANALYTICS_RETAIL'
    MUST_CHANGE_PASSWORD = FALSE
    COMMENT              = 'dbt transformation service account. Rotate password via secrets manager.';

GRANT ROLE RETAIL_TRANSFORMER TO USER SVC_DBT;

-- -----------------------------------------------------------------------------
-- SVC_INGEST — ingestion tool service account (Fivetran / Airbyte)
-- Used by: whichever ingestion tool the client uses
-- Role: RETAIL_LOADER
-- -----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS SVC_INGEST
    PASSWORD             = '<REPLACE_WITH_STRONG_PASSWORD>'
    DEFAULT_ROLE         = 'RETAIL_LOADER'
    DEFAULT_WAREHOUSE    = 'WH_LOAD'
    DEFAULT_NAMESPACE    = 'RAW_RETAIL'
    MUST_CHANGE_PASSWORD = FALSE
    COMMENT              = 'Ingestion connector service account. Fivetran or Airbyte connects as this user.';

GRANT ROLE RETAIL_LOADER TO USER SVC_INGEST;

-- -----------------------------------------------------------------------------
-- SVC_POWERBI — Power BI service account
-- Used by: Power BI dataset connections (DirectQuery or Import)
-- Role: RETAIL_BI_READER
-- -----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS SVC_POWERBI
    PASSWORD             = '<REPLACE_WITH_STRONG_PASSWORD>'
    DEFAULT_ROLE         = 'RETAIL_BI_READER'
    DEFAULT_WAREHOUSE    = 'WH_BI'
    DEFAULT_NAMESPACE    = 'ANALYTICS_RETAIL'
    MUST_CHANGE_PASSWORD = FALSE
    COMMENT              = 'Power BI service account. Read-only on mart and semantic schemas.';

GRANT ROLE RETAIL_BI_READER TO USER SVC_POWERBI;

-- -----------------------------------------------------------------------------
-- Verification queries — run after creating accounts to confirm setup
-- -----------------------------------------------------------------------------
-- SHOW USERS LIKE 'SVC_%';
-- SHOW GRANTS TO USER SVC_DBT;
-- SHOW GRANTS TO USER SVC_INGEST;
-- SHOW GRANTS TO USER SVC_POWERBI;
