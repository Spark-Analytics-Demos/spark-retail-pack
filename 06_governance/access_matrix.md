# Access Matrix — Spark Retail Pack

> **Purpose:** Documents which Snowflake role can access which database, schema, view, and sensitive column. Intended audience: security reviewers, implementation engineers, DBA, and anyone provisioning warehouse access.
>
> **Authoritative source:** §8.6 of the design document and §2.5 (Snowflake role hierarchy).
>
> **Last reviewed:** 2026-05-27 (v1 release)

---

## Role hierarchy

The pack ships seven Snowflake roles. Five are standard; two are additive privilege roles for sensitive data.

### Standard roles

| Role | Scope | Typical user |
|---|---|---|
| `RETAIL_LOADER` | **Write only** to `RAW_RETAIL` | Ingestion tool service account (Fivetran / Airbyte) |
| `RETAIL_TRANSFORMER` | Read `RAW_RETAIL`; write `ANALYTICS_RETAIL` | dbt service account |
| `RETAIL_BI_READER` | Read-only on `ANALYTICS_RETAIL.MART_*` and `ANALYTICS_RETAIL.SEMANTIC` | Power BI service account |
| `RETAIL_ANALYST` | Read on all `ANALYTICS_RETAIL` schemas; no write | Human analysts |
| `RETAIL_ADMIN` | All privileges | Engineering team only |

### Additive privilege roles (grants added on top of a standard role)

| Role | Additional access | Typical user |
|---|---|---|
| `RETAIL_PII_VIEWER` | `mart_customer.customer_pii_unmasked`; `mart_customer.customer_contact_lookup` | Customer service, compliance officers |
| `RETAIL_FINANCE_VIEWER` | `confidential`-tagged columns (unit_cost, inventory_value, spend_amount, margins) | Finance team, leadership |

---

## Access principles

- **Least privilege.** Default for new users is `RETAIL_BI_READER`. Higher access is explicitly requested and approved.
- **Separation of duty.** No human user holds `RETAIL_LOADER` or `RETAIL_TRANSFORMER`. Those are service accounts exclusively.
- **Service accounts cannot read PII or confidential data in plaintext.** Power BI, the AI assistant, and embedded analytics connect with roles that see only hashed/masked values unless specifically scoped otherwise.
- **All access changes are logged.** Snowflake `LOGIN_HISTORY`, `QUERY_HISTORY`, and `ACCESS_HISTORY` record every action.

---

## Schema-level access matrix

| Schema | `RETAIL_LOADER` | `RETAIL_TRANSFORMER` | `RETAIL_BI_READER` | `RETAIL_ANALYST` | `RETAIL_ADMIN` |
|---|---|---|---|---|---|
| `RAW_RETAIL.*` | **Write** | Read | — | — | All |
| `ANALYTICS_RETAIL.STAGING` | — | **Write** | — | Read | All |
| `ANALYTICS_RETAIL.INTERMEDIATE` | — | **Write** | — | Read | All |
| `ANALYTICS_RETAIL.CORE` | — | **Write** | — | Read | All |
| `ANALYTICS_RETAIL.MART_SALES` | — | **Write** | Read | Read | All |
| `ANALYTICS_RETAIL.MART_CUSTOMER` | — | **Write** | Read | Read | All |
| `ANALYTICS_RETAIL.MART_INVENTORY` | — | **Write** | Read | Read | All |
| `ANALYTICS_RETAIL.SEMANTIC` | — | **Write** | Read | Read | All |
| `ANALYTICS_RETAIL.METADATA` | — | **Write** | — | Read | All |

---

## Sensitive column access

Columns classified `confidential` or `pii` require an additive role beyond the standard access above.

### PII columns — require `RETAIL_PII_VIEWER`

These columns in `dim_customer` are masked (SHA-256 hash) for all roles except `RETAIL_PII_VIEWER`:

| Column | Table | Masked value available to | Plaintext available to |
|---|---|---|---|
| `email` | `dim_customer` | All readers (as hash) | `RETAIL_PII_VIEWER` only |
| `phone` | `dim_customer` | All readers (as hash) | `RETAIL_PII_VIEWER` only |
| `first_name` | `dim_customer` | All readers (as hash) | `RETAIL_PII_VIEWER` only |
| `last_name` | `dim_customer` | All readers (as hash) | `RETAIL_PII_VIEWER` only |
| `city` | `dim_customer` | All readers (as hash) | `RETAIL_PII_VIEWER` only |
| IP addresses | Staging / audit only | — | Never available in plaintext |

### Confidential columns — require `RETAIL_FINANCE_VIEWER`

| Column | Table |
|---|---|
| `unit_cost` | `dim_product`, `fact_order_lines`, `fact_inventory_snapshot`, `fact_inventory_movements` |
| `inventory_value` | `fact_inventory_snapshot` |
| `spend_amount` | `fact_marketing_spend` |
| `original_spend_amount` | `fact_marketing_spend` |

---

## Environment-specific access differences

| Environment | PII handling | Typical access |
|---|---|---|
| **dev** (`ANALYTICS_RETAIL_DEV`) | Masking **disabled**; synthetic data only | Engineers; broad access acceptable |
| **staging** (`ANALYTICS_RETAIL_STAGING`) | Masking **enabled**; restricted PII access | Engineering + QA team |
| **prod** (`ANALYTICS_RETAIL`) | Masking **enabled**; full role enforcement | Standard production roles |

The `safety_checks` macro refuses to run in dev if the target database name contains "PROD" or if the target is the `RAW_RETAIL` source. This prevents accidental production-data-in-dev exposure.

---

## Access review cadence

| Activity | Frequency | Owner |
|---|---|---|
| Review of `RETAIL_ADMIN` grants | Quarterly | Security owner (client config) |
| Review of `RETAIL_PII_VIEWER` grants | Quarterly | Security owner |
| Review of `RETAIL_FINANCE_VIEWER` grants | Quarterly | Security owner |
| Dormant account review (no login ≥ 90 days) | Monthly | Analytics Engineering |
| Service account credential rotation | Annually | Analytics Engineering |
| Role definition review | Annually | Analytics Engineering + Security |

Quarterly access review reports are auto-generated from `SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_USERS` and `SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY`. Reports route to the security owner declared in client config.

---

## PII access auditing

Every query against `mart_customer.customer_pii_unmasked` or `mart_customer.customer_contact_lookup` is logged in `SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY` with:

- Querying user identity
- Full query text
- Timestamp
- Objects accessed

The Data Operations dashboard raises an **"Unusual PII access"** alert when a single user exceeds 50 PII queries in a 24-hour window. This alert routes to the security owner.

---

## Granting access (implementation steps)

To grant a user `RETAIL_ANALYST` access plus `RETAIL_FINANCE_VIEWER`:

```sql
-- Run as RETAIL_ADMIN
GRANT ROLE RETAIL_ANALYST TO USER <username>;
GRANT ROLE RETAIL_FINANCE_VIEWER TO USER <username>;
```

All grants are subject to approval by the domain business owner (per `06_governance/ownership.yml`) before execution.
