# PII Inventory — Spark Retail Pack

> **Purpose:** Complete reference of every personally identifiable field in the canonical core. Intended audience: compliance officers, data protection officers, procurement security reviewers, and implementation engineers.
>
> **Authoritative source:** §8.5 of the design document (`01_design_docs/08_governance_baseline.md`).
>
> **Last reviewed:** 2026-05-27 (v1 release)

---

## Governing principles

1. **PII is hashed by default, in plaintext by exception.** Every PII column is masked via SHA-256 hash with a client-specific salt before landing in the gold layer. Plaintext access requires the `RETAIL_PII_VIEWER` role.
2. **Hashed identifiers are not PII.** `email_hash` and `phone_hash` are used for joins and metrics; they appear in internal-classified columns accessible to all warehouse readers.
3. **Source systems own the plaintext.** The warehouse derives analytical views. Source data (Shopify, Klaviyo) retains its own copy. Warehouse erasure deletes the warehouse copy; clients must also handle source-system erasure through those platforms.
4. **IP addresses are not exposed in plaintext at all.** Hashed at staging; no plaintext path exists anywhere in the warehouse.

---

## Full PII field inventory

| Table | Column | PII category | Hash type | Plaintext path | Regulatory basis |
|---|---|---|---|---|---|
| `dim_customer` | `email` | Contact — direct identifier | SHA-256 + client salt | `mart_customer.customer_pii_unmasked` via `RETAIL_PII_VIEWER` | GDPR Art. 4(1); CCPA §1798.140(o) |
| `dim_customer` | `phone` | Contact — direct identifier | SHA-256 after E.164 normalisation | Same as above | GDPR Art. 4(1); CCPA §1798.140(o) |
| `dim_customer` | `first_name` | Name — direct identifier | SHA-256 + client salt | Same as above | GDPR Art. 4(1); CCPA §1798.140(o) |
| `dim_customer` | `last_name` | Name — direct identifier | SHA-256 + client salt | Same as above | GDPR Art. 4(1); CCPA §1798.140(o) |
| `dim_customer` | `city` | Location — indirect identifier | SHA-256 + client salt | Same as above | GDPR Art. 4(1); CCPA §1798.140(o) — identifying when combined with name |
| `fact_orders` (various) | `ip_address_hash` | Network identifier | SHA-256 at staging; no plaintext stored | No plaintext path exists | GDPR Art. 4(1); CCPA §1798.140(o) |
| `fact_web_sessions` | `user_pseudo_id` | Pseudonym | Anonymised at source by GA4 | n/a — never PII in the warehouse | Lower risk; treated as pseudonymised per GDPR Art. 4(5) |

---

## Masking implementation

PII fields are masked using the `pii_mask` macro in `02_dbt_core/macros/pii_mask.sql`.

```sql
-- In dim_customer.sql — dual-storage pattern:
{{ pii_mask('email', method='hash') }}  as email_hash,  -- always present; used for joins
{{ pii_mask('email', method='hash') }}  as email,       -- masked by default in gold layer
```

Configuration in `dbt_project.yml`:

```yaml
vars:
  pii_masking_enabled: true            # default; set false only in dev with synthetic data
  pii_hashing_method: 'sha256'
  pii_hash_salt: "{{ env_var('PII_HASH_SALT') }}"
```

The hash salt is stored in the client's secret manager (AWS Secrets Manager, Azure Key Vault, or equivalent). It **never** appears in code, warehouse metadata, or documentation.

---

## Plaintext access path

Plaintext PII is exposed only via specific mart views. These views are **not** accessible to `RETAIL_ANALYST` or `RETAIL_BI_READER`. Access requires the `RETAIL_PII_VIEWER` role (granted by approval; logged; reviewed quarterly).

| View | Purpose | Returns |
|---|---|---|
| `mart_customer.customer_pii_unmasked` | Full PII profile for a named customer | email, phone, first_name, last_name, city |
| `mart_customer.customer_contact_lookup` | Customer service lookup — one customer at a time | email, phone for a given `customer_id` only |

Every query against these views is logged via Snowflake `ACCESS_HISTORY`. The Data Operations dashboard raises an **"Unusual PII access"** alert when a single user runs more than 50 PII queries in a 24-hour window.

---

## Regulatory scope by PII category

| Category | Columns | GDPR Article 4 | CCPA | Notes |
|---|---|---|---|---|
| Direct identifiers | `email`, `phone`, `first_name`, `last_name` | (1) Personal data | §1798.140(o) | Core PII |
| Online identifiers | IP addresses | (1) Personal data | §1798.140(o) | Never in plaintext in warehouse |
| Location | `city` (when combined with name) | (1) Personal data | §1798.140(o) | Hashed as precaution |
| Pseudonymised | `email_hash`, `phone_hash`, `user_pseudo_id` | (5) Pseudonymised | Treated as personal information | Lower risk; still regulated |
| Special categories | None | Article 9 | — | The pack does not collect special-category data |

---

## Consent management

Beyond erasure, ongoing consent state from source systems is tracked:

| Column | Table | Meaning |
|---|---|---|
| `marketing_consent` | `dim_customer` | Current marketing consent; Klaviyo value wins per §4.3 |
| `email_subscribed` | `dim_customer` | Email channel consent |
| `sms_subscribed` | `dim_customer` | SMS channel consent |

Mart views for marketing audiences (`mart_customer.marketing_audience`) automatically exclude customers where `marketing_consent = FALSE` or `email_subscribed = FALSE`. The Customer 360 dashboard's active-customer KPIs do **not** exclude opted-out customers — they measure activity, not marketability.

---

## Erasure

When a customer exercises GDPR Article 17 right-to-erasure or CCPA opt-out:

- Their `customer_id` is added to `seeds/erasure_requests.csv`
- The next `dbt build` executes the `customer_erasure` macro
- All PII fields in `dim_customer`, `fact_orders`, `fact_web_sessions`, and `fact_email_engagement` are overwritten with a cryptographic redaction hash
- The customer row **remains** for analytical integrity with no identifying information
- The erasure is logged in `metadata.erasure_log` with a `confirmation_hash` for audit

See `06_governance/erasure_runbook.md` for the full step-by-step procedure.

---

## Hash salt rotation

PII hash salts are client-specific and rotated annually by default. Rotation does not break analytics — historical hashed values remain internally consistent. New rows use the new salt. Hash continuity within a customer is maintained because each customer is rehashed with the same salt for their entire lifetime in the warehouse.

**Important:** The old PII salt must never be reused or documented after rotation. If a salt is accidentally exposed, treat it as a security incident and rotate immediately.

---

## What this pack does NOT handle

- **Children's data (COPPA / GDPR Art. 8):** Mid-market D2C retail rarely deals with children as purchasers. Clients in toy or children's verticals requiring COPPA handling should contact Spark for a custom extension.
- **Special-category data (GDPR Art. 9):** Health, religion, biometrics, political opinion. Not collected. If adjacent verticals require this, contact Spark.
- **Source-system erasure:** The `customer_erasure` macro erases the warehouse copy only. Clients must separately handle erasure requests in Shopify, Klaviyo, Stripe, etc.
