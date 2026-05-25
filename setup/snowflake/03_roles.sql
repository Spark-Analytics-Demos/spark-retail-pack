-- =============================================================================
-- Spark Retail Pack — Role Hierarchy
-- Section 2.5 | PHASE_0_CHECKLIST §0.2
--
-- Seven custom roles. Two patterns:
--   Primary roles  — mutually exclusive job functions (LOADER, TRANSFORMER, etc.)
--   Additive roles — stack on top of a primary role for elevated data access
--                    (PII_VIEWER, FINANCE_VIEWER)
--
-- Snowflake role hierarchy: ACCOUNTADMIN > SYSADMIN > custom roles.
-- All custom roles are granted to SYSADMIN so admin users can operate as them.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- Primary functional roles
-- -----------------------------------------------------------------------------

CREATE ROLE IF NOT EXISTS RETAIL_ADMIN
    COMMENT = 'Engineering team only. Full privileges across all Retail Pack objects. Assigned to humans, not service accounts.';

CREATE ROLE IF NOT EXISTS RETAIL_LOADER
    COMMENT = 'Ingestion service account role. Write access to RAW_RETAIL only. No access to analytics databases.';

CREATE ROLE IF NOT EXISTS RETAIL_TRANSFORMER
    COMMENT = 'dbt service account role. Read on RAW_RETAIL, read/write on all ANALYTICS_RETAIL* databases.';

CREATE ROLE IF NOT EXISTS RETAIL_ANALYST
    COMMENT = 'Analytics team — read-only on all ANALYTICS_RETAIL schemas. Uses WH_ADHOC.';

CREATE ROLE IF NOT EXISTS RETAIL_BI_READER
    COMMENT = 'Power BI service account role. Read-only on MART_* and SEMANTIC schemas only. Uses WH_BI.';

-- -----------------------------------------------------------------------------
-- Additive elevated-access roles (Section 2.5, Section 8.6)
-- These grant access to sensitive data ON TOP OF a primary role.
-- A user would hold, e.g., RETAIL_ANALYST + RETAIL_PII_VIEWER.
-- -----------------------------------------------------------------------------

CREATE ROLE IF NOT EXISTS RETAIL_PII_VIEWER
    COMMENT = 'Additive. Grants access to PII-in-clear mart views (e.g. customer_pii_unmasked). Customer service and compliance teams only.';

CREATE ROLE IF NOT EXISTS RETAIL_FINANCE_VIEWER
    COMMENT = 'Additive. Grants access to confidential-tagged columns (cost, margin, ad spend). Finance and leadership only.';

-- -----------------------------------------------------------------------------
-- Role hierarchy grants
-- Grant all custom roles to SYSADMIN so the admin can assume any role.
-- Grant SYSADMIN to RETAIL_ADMIN so retail admins get full warehouse control.
-- -----------------------------------------------------------------------------

GRANT ROLE RETAIL_LOADER        TO ROLE SYSADMIN;
GRANT ROLE RETAIL_TRANSFORMER   TO ROLE SYSADMIN;
GRANT ROLE RETAIL_ANALYST       TO ROLE SYSADMIN;
GRANT ROLE RETAIL_BI_READER     TO ROLE SYSADMIN;
GRANT ROLE RETAIL_PII_VIEWER    TO ROLE SYSADMIN;
GRANT ROLE RETAIL_FINANCE_VIEWER TO ROLE SYSADMIN;
GRANT ROLE RETAIL_ADMIN         TO ROLE SYSADMIN;

GRANT ROLE SYSADMIN TO ROLE RETAIL_ADMIN;
