# Section 8: Governance Baseline

> **Document status:** Draft v1
> **Audience:** Procurement reviewers, security teams, data protection officers, enterprise clients, implementation consultants, compliance auditors
> **Purpose:** Consolidate the governance disciplines built into the Spark Retail Pack — ownership, classification, PII handling, access control, lineage, retention, and audit. Much of this has been specified in earlier sections; this section is the single document a procurement team can read to understand "how does this product handle our data responsibly."

---

## 8.1 Why this section exists

Governance is fragmented across the design document by design. PII handling sits where the columns are defined (Section 4 Part 1, §4.15). Audit columns live where the model schema is (Section 4 Part 2, §4.31). Erasure macros live with implementation standards (Section 4 Part 3, §4.41). Access roles live with the Snowflake setup (Section 2, §2.5).

That distribution is appropriate for **engineering reference** — the rules live near the code they govern. It is inappropriate for **procurement review** — a security team should not have to read seven sections to answer "do you mask PII?"

Section 8 is the consolidated answer to that question. Every governance topic in this document is either defined here or **referenced** here, with pointers to the authoritative definition elsewhere. Where this section conflicts with another section, the other section wins — Section 8 is a synthesis, not a re-specification.

---

## 8.2 Governance principles

Five principles underpin every governance decision in the pack:

1. **The warehouse is never the system of record for source data.** Source systems own their data; the warehouse derives analytical views. This shapes how we handle deletion, retention, and accountability.
2. **PII is hashed by default, in plaintext by exception.** Anyone querying the gold layer sees hashes. Plaintext access requires a specific role, a specific view, and an auditable reason.
3. **Every row is traceable to its origin.** Eight audit columns per table (§8.7 below) answer "where did this come from" without forensic SQL.
4. **Governance is configuration, not heroics.** Ownership, classification, retention, and access rules live in YAML files that ship with the pack. Clients edit the YAML — they don't build governance from scratch.
5. **Compliance regulations are engineering features.** GDPR right-to-erasure isn't a process; it's a macro. CCPA opt-out isn't a procedure; it's a config flag. Treating compliance as code is the only way to handle it at scale.

These principles are not aspirations — every one is implemented in the v1 pack and verifiable by inspection.

---

## 8.3 Data ownership

Every domain in the canonical model has a designated business owner (defines what the data means) and a technical steward (maintains the implementation). This is enforced via tags on dbt models and surfaced in the data catalog.

### Domain ownership matrix

The matrix below is the v1 default. Clients adjust to match their organization in `06_governance/ownership.yml`.

| Domain | Tables | Business owner | Technical steward |
|---|---|---|---|
| **Customer** | `dim_customer`, `fact_customer_state_daily` | Growth / CRM team | Analytics engineering |
| **Sales** | `fact_orders`, `fact_order_lines`, `fact_refunds`, `dim_payment_method` | Finance | Analytics engineering |
| **Product** | `dim_product`, `dim_supplier` (v1.5) | Merchandising | Analytics engineering |
| **Inventory** | `fact_inventory_snapshot`, `fact_inventory_movements`, `dim_warehouse_location` | Operations / Supply Chain | Analytics engineering |
| **Marketing** | `fact_marketing_spend`, `fact_web_sessions`, `dim_marketing_campaign` | Marketing | Analytics engineering |
| **Email/CRM** | `fact_email_engagement`, `dim_email_campaign` | Marketing (Email) | Analytics engineering |
| **Reference data** | `dim_date`, `dim_channel`, `dim_geography` | Analytics engineering (shared) | Analytics engineering |

### What ownership means concretely

| Responsibility | Business owner | Technical steward |
|---|---|---|
| Approves changes to KPI definitions in the domain | ✓ | (reviews) |
| Approves changes to canonical column meaning | ✓ | (reviews) |
| Approves new dimensions/facts in the domain | ✓ | (reviews) |
| Investigates data quality issues | (escalation) | ✓ |
| Maintains source mappings | (reviews) | ✓ |
| Reviews access requests | ✓ | (executes) |
| Signs off on quarterly data quality report | ✓ | (prepares) |

### How ownership is enforced in code

Every dbt model carries an `owner` tag in its meta:

```yaml
# models/core/_core__models.yml
- name: dim_customer
  meta:
    owner: growth_team
    technical_steward: analytics_engineering
    domain: customer
    pii_present: true
```

A CI check enforces that every model has both an `owner` and `technical_steward`. The dbt docs site surfaces ownership for every table, and the proprietary Data Operations dashboard groups data quality alerts by owner so issues route correctly.

### Ownership reviews

Domain ownership is reviewed quarterly. If a business team reorganizes (e.g., "growth" splits into "acquisition" and "retention"), the YAML file is updated and propagates everywhere. No SQL changes required.

---

## 8.4 Data classification

Every column in the canonical core is classified into one of five tiers. Classification drives masking behavior, access control, and audit-log routing.

### Classification taxonomy

| Tier | Definition | Examples | Masking default | Access |
|---|---|---|---|---|
| **public** | No restriction; safe to expose anywhere | Product category, country code, order status | None | All warehouse readers |
| **internal** | Business-confidential but not personal | Internal segments, channel groupings, conversion rates | None | All warehouse readers |
| **confidential** | Sensitive business data; financial impact if exposed | Unit cost, supplier terms, margin, internal financials | None | Restricted role |
| **restricted** | Highly sensitive; legal/regulatory impact | Tax IDs, full payment card details (we don't store these) | Hashed | Privileged role only, logged |
| **pii** | Personally identifiable; regulatory protection required | Email, phone, full name, address, IP | Hashed | Privileged role only, logged |

### How classification is declared

Every column declares its classification in `schema.yml`:

```yaml
- name: dim_customer
  columns:
    - name: email
      meta:
        classification: pii
        masking_method: sha256_hash
        pii_category: contact_information
      description: Customer email; masked by default
    - name: customer_segment
      meta:
        classification: internal
      description: Internal RFM-derived segment
    - name: unit_cost
      meta:
        classification: confidential
      description: Cost of goods at time of sale
```

### Classification by canonical column

A consolidated view of how the canonical core's columns classify. This is the table procurement teams ask for.

**`dim_customer`**

| Column | Classification | Notes |
|---|---|---|
| `customer_id`, `customer_sk`, `email_hash`, `phone_hash` | internal | Hashed identifiers — not directly PII |
| `email`, `phone` | **pii** | Masked unless PII viewer |
| `first_name`, `last_name` | **pii** | Masked |
| `city` | **pii** | Combined with name = identifying |
| `postal_code_hash` | internal | Hashed |
| `country_code`, `region` | internal | Not identifying alone |
| `customer_segment`, `customer_status`, `acquisition_channel` | internal | |
| `marketing_consent`, `email_subscribed`, `sms_subscribed` | internal | Regulatory but not PII |
| `is_b2b_customer`, `customer_tags` | internal | |
| Audit columns (`_source_system`, etc.) | internal | |

**`fact_orders`**

| Column | Classification | Notes |
|---|---|---|
| `order_id`, `customer_id`, `customer_sk` | internal | |
| `customer_email_hash_at_order` | internal | Hashed |
| `gross_amount`, `net_amount`, etc. | internal | Order amounts |
| `unit_cost` (via line items) | **confidential** | |
| `ip_address_hash` | internal | Hashed |
| `utm_*`, `referrer_url`, `landing_page_url` | internal | |
| Order status, financial status, channel, geography refs | internal | |

**`dim_product`**

| Column | Classification | Notes |
|---|---|---|
| Most fields | public | Product attributes are non-sensitive |
| `unit_cost` | **confidential** | Cost data |

**`fact_marketing_spend`**

| Column | Classification | Notes |
|---|---|---|
| `spend_amount`, `original_spend_amount` | **confidential** | Ad spend disclosure |
| Everything else | internal | |

**`fact_inventory_snapshot`, `fact_inventory_movements`**

| Column | Classification | Notes |
|---|---|---|
| `inventory_value`, `unit_cost` | **confidential** | |
| Stock quantities | internal | |
| `is_slow_mover`, `is_overstock` | internal | |

**`fact_email_engagement`, `fact_web_sessions`**

| Column | Classification | Notes |
|---|---|---|
| `customer_id`, `customer_sk` | internal | |
| `user_pseudo_id` | internal | Anonymized at source |
| Event metadata, device, browser | internal | |

### Classification at scale

For a typical mid-market client deployment, the classification distribution is approximately:

- **public:** ~30% of columns (product attributes, dates, statuses, reference data)
- **internal:** ~55% of columns (most business data, hashed identifiers)
- **confidential:** ~5% of columns (costs, margins, spend)
- **restricted:** ~1% of columns (rarely used in v1)
- **pii:** ~9% of columns (personal data, masked by default)

These percentages are illustrative — they reflect the expected distribution given the canonical model in Section 4, not measured values from a deployed client. Actual distributions vary based on client customizations (e.g., heavy B2B clients have more confidential pricing columns).

This is configured once and rarely changes. The CI documentation discipline (Section 4 Part 3, §4.45) ensures new columns get a classification before being merged.

---

## 8.5 PII inventory and handling

PII handling is the governance topic with the most regulatory exposure. This subsection consolidates the rules across the pack.

### Full PII inventory

These are every PII column in the canonical core. Each ships with masking-by-default and access logging.

| Table | Column | PII category | Hash type | Plaintext available via |
|---|---|---|---|---|
| `dim_customer` | `email` | Contact | SHA-256 | `mart_customer.customer_pii_unmasked` (PII viewer role) |
| `dim_customer` | `phone` | Contact | SHA-256 (after E.164 normalize) | Same |
| `dim_customer` | `first_name` | Name | SHA-256 | Same |
| `dim_customer` | `last_name` | Name | SHA-256 | Same |
| `dim_customer` | `city` | Location | SHA-256 (when in combination with name) | Same |
| `fact_web_sessions` | `user_pseudo_id` | Pseudonym | (already anonymized at source by GA4) | n/a — never PII |
| Various | IP addresses | Network identifier | SHA-256 | Not exposed in plaintext at all |

### Masking implementation

Per Section 4 Part 1 §4.15, every PII column has a dual-storage pattern:

```sql
-- In dim_customer.sql:
{{ pii_mask('email', method='hash') }} as email_hash,   -- always present, used for joins
{{ pii_mask('email', method='hash') }} as email,        -- masked by default
```

The `pii_mask` macro respects environment configuration:

```yaml
# dbt_project.yml
vars:
  pii_masking_enabled: true   # default
  pii_hashing_method: 'sha256'
  pii_hash_salt: "{{ env_var('PII_HASH_SALT') }}"   # client-specific salt
```

The salt is stored in the client's secret manager (Section 2 §2.9) and never appears in code or in the warehouse itself.

### Plaintext access pattern

Plaintext PII is exposed only via specific mart views (not directly from `dim_customer`):

- `mart_customer.customer_pii_unmasked` — joins `dim_customer` with raw PII for the named customer
- `mart_customer.customer_contact_lookup` — limited view for customer service: returns email + phone for a given `customer_id`, nothing else

Access to these views requires the `RETAIL_PII_VIEWER` role (Section 2 §2.5). Every query against them is logged via Snowflake `ACCESS_HISTORY` with the querying user, query text, and timestamp. The Data Operations dashboard surfaces an "Unusual PII access" alert when a user runs >50 PII queries in a day.

### PII categories and regulatory scope

| Category | Includes | GDPR Article 4 | CCPA Sec. | Other |
|---|---|---|---|---|
| Direct identifiers | Name, email, phone | (1) Personal data | 1798.140(o) | |
| Online identifiers | IP, cookie ID, device ID | (1) Personal data | 1798.140(o) | |
| Location | Postal code, city + name | (1) Personal data | 1798.140(o) | |
| Pseudonymized | Hashed email, GA4 pseudo ID | (5) Pseudonymized data | (treated as PI) | Lower risk but still regulated |
| Special categories | (none in pack) | Article 9 | | Not collected |

The pack does **not** handle special-category data (health, religion, biometrics, political opinion, etc.). Clients in adjacent verticals (healthcare, financial services) requiring special-category handling should contact Spark for a custom extension.

### Salting and rotation

PII hash salts are client-specific and rotated annually by default. Rotation does not break analytics — the historical hashed values remain valid; only new rows use the new salt. Hash continuity within a customer is maintained because each customer is rehashed using the same salt for their lifetime in the warehouse.

A salt rotation runbook is in the operational documentation (referenced from Section 13, placeholder).

---

## 8.6 Access control

Access to the warehouse is role-based, enforced at Snowflake, and inherited by every downstream consumer (Power BI, AI assistant, embedded analytics).

### Standard role hierarchy

The pack ships seven default Snowflake roles (also defined in Section 2 §2.5):

| Role | Permissions | Typical user |
|---|---|---|
| `RETAIL_LOADER` | Write only to `RAW_RETAIL` | Ingestion tool service account (Fivetran, Airbyte) |
| `RETAIL_TRANSFORMER` | Read `RAW_RETAIL`; write `ANALYTICS_RETAIL` | dbt service account |
| `RETAIL_BI_READER` | Read-only on `ANALYTICS_RETAIL.MART_*` and `ANALYTICS_RETAIL.SEMANTIC` | Power BI service account |
| `RETAIL_ANALYST` | Read on all `ANALYTICS_RETAIL` schemas; no write | Human analysts |
| `RETAIL_ADMIN` | All privileges | Engineering team only |

Two **additional** roles ship for sensitive data:

| Role | Permissions | Typical user |
|---|---|---|
| `RETAIL_PII_VIEWER` | Adds access to `mart_customer.customer_pii_unmasked` and similar PII-in-clear views | Customer service, compliance officers |
| `RETAIL_FINANCE_VIEWER` | Adds access to `confidential`-tagged columns (cost, margin, spend) | Finance team, leadership |

### Access principles

- **Least privilege.** Default role is `RETAIL_BI_READER`. Higher access is requested and approved.
- **Separation of duty.** No human user has `RETAIL_LOADER` or `RETAIL_TRANSFORMER`. Those are service accounts only.
- **Service accounts cannot read PII or confidential data in plaintext.** Power BI, the AI assistant, and embedded analytics all connect with roles that see hashed/masked data unless specifically scoped to a PII-allowed dashboard.
- **All access changes are logged.** Snowflake's `LOGIN_HISTORY`, `QUERY_HISTORY`, and `ACCESS_HISTORY` track every action. Logs are retained for 1 year by default.

### Access review cadence

| Activity | Frequency |
|---|---|
| Review of `RETAIL_ADMIN` grants | Quarterly |
| Review of `RETAIL_PII_VIEWER` and `RETAIL_FINANCE_VIEWER` grants | Quarterly |
| Review of dormant accounts (no login in 90 days) | Monthly |
| Review of service account credentials | Annually (with rotation) |
| Review of role definitions themselves | Annually |

A quarterly access review report is auto-generated from `ACCOUNT_USAGE.GRANTS_TO_USERS` and `ACCOUNT_USAGE.LOGIN_HISTORY`. Reports route to the security owner declared in client config.

### Multi-environment isolation

Per Section 4 Part 3 §4.43, dev/staging/prod environments use separate Snowflake databases (`ANALYTICS_RETAIL_DEV`, `ANALYTICS_RETAIL_STAGING`, `ANALYTICS_RETAIL`). Access patterns differ:

| Environment | PII handling | Typical access |
|---|---|---|
| **dev** | Masking disabled; synthetic data only | Engineers; broad access |
| **staging** | Masking enabled; restricted PII access | Engineering + QA |
| **prod** | Masking enabled; full role enforcement | Standard production access |

A common production-data-in-dev pitfall is explicitly prevented: the pack's `safety_checks` macro refuses to run in dev against a database name containing "PROD" or against the `RAW_RETAIL` source.

---

## 8.7 Audit and lineage

This subsection summarizes Section 4 Part 2 §4.31 from a governance perspective. Refer to the original for full implementation detail.

### What is tracked

Every row in the canonical core carries eight audit columns:

| Column | Answers |
|---|---|
| `_source_system` | Where did this come from? |
| `_source_record_id` | What's its original ID at source? |
| `_extracted_at` | When did it leave the source? |
| `_loaded_at` | When did it land in our warehouse? |
| `_dbt_invocation_id` | Which dbt run produced it? |
| `_dbt_model` | Which model created it? |
| `_record_hash` | Has it changed since I last looked? |
| `_is_deleted_at_source` | Is it still active at source? |

Plus the run-level `metadata.dbt_run_log` table tracking every dbt invocation.

### Lineage capability

dbt's manifest provides full model-level lineage out of the box. The pack supplements with:

- **`metadata.lineage_edges` view** — flat, SQL-queryable lineage (which model depends on which)
- **`exposures.yml`** — declared downstream consumers (Power BI dashboards, ML models) so impact analysis includes them
- **dbt docs site** — visual lineage graph delivered to every client

### Lineage questions clients ask, and the SQL that answers them

| Question | Approach |
|---|---|
| "Why is this number different from last month?" | Filter `fact_orders` by `_dbt_invocation_id` from each run; compare `_record_hash` values |
| "What's our source-to-report latency?" | `AVG(datediff('minute', _extracted_at, _loaded_at))` per source |
| "Which dashboards depend on `dim_customer`?" | Query `metadata.lineage_edges WHERE upstream_model = 'dim_customer'` |
| "What did the data look like yesterday?" | Snowflake Time Travel: `SELECT * FROM fact_orders AT(OFFSET => -86400)` |
| "Show me every row produced by the failed run last night" | Join `fact_orders` to `metadata.dbt_run_log WHERE status = 'error'` |

### Time Travel and zero-copy cloning

Snowflake's native features extend governance capability:

- **Time Travel** is set to 7 days on `ANALYTICS_RETAIL` (per Section 2 §2.9). Any point-in-time query within the window is possible.
- **Zero-copy cloning** is used to create instant audit snapshots for compliance review without doubling storage.
- **Fail-safe** (7 additional days after Time Travel expires) provides last-resort recovery via Snowflake support.

These are not bolted on — they're standard Snowflake features the pack leverages for governance.

---

## 8.8 Data quality governance

Beyond row-level audit, the pack monitors ongoing data quality and surfaces issues to the responsible owner.

### Test categories (consolidated from Section 4 Part 3 §4.37)

| Category | Examples | Default severity |
|---|---|---|
| Schema tests | `not_null`, `unique`, `accepted_values`, `relationships` | error |
| Source freshness | `warn_after: 6 hours`, `error_after: 24 hours` (Shopify) | warn / error |
| Business rule | `net_amount >= 0`, `refunded_amount <= net_amount` | error |
| Singular | Complex SQL tests in `tests/` | varies |
| Statistical | Anomaly detection on key metrics (v2 with Elementary) | warn |

### Quality SLAs by domain

The pack ships default SLAs per domain. Clients can tighten or relax per environment.

| Domain | Freshness warn | Freshness error | Quality test errors allowed |
|---|---|---|---|
| Sales (Shopify orders) | 6 hours | 24 hours | 0 |
| Sales (Stripe reconciliation) | 12 hours | 48 hours | 0 (must reconcile) |
| Customer (Klaviyo events) | 6 hours | 24 hours | < 0.1% of rows |
| Customer (GA4 sessions) | 24 hours | 48 hours (GA4 has its own latency) | < 0.5% of rows |
| Customer (Meta Ads) | 12 hours | 48 hours | < 0.1% of rows |
| Inventory snapshots | 24 hours | 48 hours | 0 |

### Quality alert routing

Test failures route to the owning team's channel:

- Sales test failures → `#data-alerts-sales` (Slack)
- Customer test failures → `#data-alerts-customer`
- Inventory test failures → `#data-alerts-inventory`
- Cross-domain failures → `#data-alerts-platform`

Routing is config-driven (`06_governance/alert_routing.yml`), not hardcoded.

### Quality reports

Monthly automated quality reports include:

- Test pass rate by domain
- Source freshness SLA compliance
- Total rows quarantined vs. processed
- Top 10 most-failed tests with trend
- Open vs. resolved data incidents

Reports route to business owners (per §8.3) for sign-off.

---

## 8.9 Retention policies

Different data types require different retention horizons. The pack ships defaults; clients adjust per regulatory and operational needs.

### Default retention by data type

| Data type | Bronze | Silver/Gold | Marts | Time Travel | Fail-safe |
|---|---|---|---|---|---|
| Order transactions | 90 days | Indefinite | Indefinite | 7 days | 7 days |
| Customer profiles | 90 days | Indefinite (until erasure) | Same | 7 days | 7 days |
| Marketing spend | 90 days | Indefinite | Indefinite | 7 days | 7 days |
| Web sessions | 30 days | 24 months default | 24 months | 7 days | 7 days |
| Email engagement | 90 days | 24 months default | 24 months | 7 days | 7 days |
| Inventory snapshots | 30 days | 24 months daily, then monthly archive | 24 months | 7 days | 7 days |
| Customer state daily | (n/a, generated) | 24 months daily, then monthly archive | 24 months | 7 days | 7 days |
| Audit logs (`metadata.*`) | n/a | 12 months active, 5 years archived | n/a | 7 days | 7 days |

### Why defaults differ from "indefinite"

Some data types degrade in analytical value over time but accumulate in storage cost and regulatory liability:

- **Web sessions** lose value beyond 2 years for most analytical purposes; older sessions are aggregated, not retained at row grain.
- **Email engagement** is most valuable for recent retention analysis; older events are aggregated.
- **Daily snapshots** of customer state and inventory accumulate massive row counts; the pack archives older snapshots to monthly grain after 24 months.

### Retention configurability

Retention is set per environment in `06_governance/retention.yml`:

```yaml
retention:
  web_sessions:
    daily_grain_months: 24
    archive_grain: monthly
    archive_retention_months: 60
  customer_state_daily:
    daily_grain_months: 24
    archive_grain: monthly
    archive_retention_months: 84   # 7 years for cohort analysis
```

Clients in regulated industries (financial-adjacent retail, healthcare retail) typically extend retention to 7 years. Clients in privacy-strict jurisdictions (EU + age-gated content) typically shorten to 13 months for non-essential data.

### Retention vs. erasure

Retention is **time-based, automatic**. Erasure is **event-driven, on request**. They interact: a customer requesting GDPR erasure has their data deleted regardless of retention policy. Retention policies are about default longevity; erasure overrides them.

---

## 8.10 Right-to-erasure and consent management

The pack implements GDPR Article 17 (right-to-erasure), CCPA opt-out, and similar regulatory rights as code, not as process.

### The erasure flow (per Section 4 Part 3 §4.41)

1. Client receives an erasure request through their compliance system.
2. Client validates the request (identity verification, no overriding legal hold).
3. Client adds the customer's `customer_id` to `seeds/erasure_requests.csv`:

   ```csv
   customer_id, request_date, ticket_id, scope, legal_basis
   abc123, 2026-04-15, GDPR-7421, full_erasure, gdpr_article_17
   def456, 2026-04-20, CCPA-2289, marketing_only, ccpa_1798_105
   ```

4. Next dbt build executes the `customer_erasure` macro:
   - `full_erasure`: All PII fields hashed-and-redacted across `dim_customer`, `fact_orders`, `fact_web_sessions`, `fact_email_engagement`. Customer row remains for analytical integrity (no identifying info).
   - `marketing_only`: Subscription flags set to FALSE; customer removed from active marketing audiences.

5. Erasure is logged in `metadata.erasure_log`:

   | Column | Description |
   |---|---|
   | `customer_id` | Erased customer |
   | `ticket_id` | Client's compliance ticket |
   | `legal_basis` | GDPR article / CCPA section / other |
   | `scope` | full or marketing_only |
   | `requested_at` | Client-recorded request date |
   | `executed_at` | When the macro ran |
   | `executed_by` | dbt invocation ID |
   | `confirmation_hash` | Cryptographic confirmation row for audit |

### Why analytical retention survives erasure

A customer who placed 50 orders contributes to revenue analytics regardless of their identity. The pack preserves the order events (with PII stripped) so analytical history remains intact while individual identification is destroyed.

This is the industry-standard pattern for analytics warehouses post-GDPR. Verification:

- The Article 29 Working Party guidance (now EDPB) explicitly accepts pseudonymization + aggregation as sufficient for analytical retention beyond erasure
- Major data warehousing vendors (Snowflake, Databricks, BigQuery) document this pattern

### Consent management

Beyond erasure, the pack respects ongoing consent state from source systems:

- `dim_customer.marketing_consent` reflects current consent (Klaviyo wins per Section 4 Part 1 §4.3)
- `email_subscribed`, `sms_subscribed` reflect channel-level consent
- Mart views for marketing audiences (`mart_customer.marketing_audience`) automatically exclude opted-out customers
- The Customer 360 dashboard's "Active Customers" KPI continues to include opted-out customers (they still exist); only marketing-targeting views filter them

### Children's data

The pack does **not** include explicit handling for children's data (COPPA, GDPR Article 8). Mid-market D2C retail rarely deals with children's data as customers (parents typically are the purchasers). Clients in toy/children's verticals requiring COPPA handling should contact Spark for an extension; the framework supports adding age-gating fields and consent records.

---

## 8.11 Tax and regulatory reporting

Beyond privacy, governance includes traceability for tax and regulatory reporting.

### Tax reporting capability

The pack supports tax filing workflows but does not file taxes:

- `fact_orders.tax_amount` is the gross tax collected per order
- `dim_geography.is_tax_jurisdiction` flags regions with their own tax rules
- The `mart_sales.tax_summary_by_jurisdiction` view aggregates tax by jurisdiction and period
- Refunded tax is tracked separately in `fact_refunds.refund_tax_amount`

Net tax owed (collected minus refunded, minus tax exemptions) is computed in the tax mart. The actual filing — paper or e-file — is out of pack scope. Clients use Avalara, TaxJar, or manual filing on top of the pack's outputs.

### Regulatory audit trail

For a regulatory inquiry asking "show me every order placed by EU customers in Q1 2026":

```sql
SELECT 
  o.order_id, o.order_date, o.net_amount, o.tax_amount,
  c.country_code, c.email_hash
FROM fact_orders o
JOIN dim_customer c ON o.customer_id = c.customer_id
JOIN dim_geography g ON c.country_code = g.country_code
WHERE g.country_region = 'EMEA'
  AND o.order_date BETWEEN '2026-01-01' AND '2026-03-31'
  AND o.order_status NOT IN ('cancelled');
```

This kind of query is the warehouse's strength. Regulators almost always require: identification of records in scope, computation over those records, and proof of computation methodology. The pack's lineage + audit columns provide all three.

### Industry-specific compliance (deferred to v2)

Several industry-specific compliance frameworks are not in v1 but planned:

- **PCI-DSS** — out of v1 scope because the pack does not store card data. Clients with PCI obligations on adjacent systems still benefit from the pack's analytical separation.
- **HIPAA** — out of v1 scope. Retail-adjacent healthcare (e.g., supplements, OTC) requires custom handling.
- **SOC 2 / ISO 27001** — out of v1 scope as pack-level certification. Clients pursuing SOC 2 themselves can use the pack's audit columns and access logs as supporting evidence.

These are documented as v2 considerations in Section 13's placeholder.

---

## 8.12 Governance artifacts shipped with the pack

The pack ships with concrete governance files clients customize. These live in `06_governance/`:

| File | Purpose | Example content |
|---|---|---|
| `ownership.yml` | Domain ownership matrix | Domain → business owner → technical steward |
| `classification.yml` | Column-level classification rules | Default classifications for every canonical column |
| `pii_inventory.md` | Full list of PII fields | Annotated reference for compliance teams |
| `retention.yml` | Per-table retention policies | Configurable timelines and archive strategies |
| `access_matrix.md` | Role-to-data mapping | Which role sees which schema/view |
| `alert_routing.yml` | DQ alert routing | Domain → Slack channel → escalation |
| `erasure_runbook.md` | GDPR/CCPA erasure procedure | Step-by-step for compliance team |
| `audit_log_retention.yml` | Audit log retention | Per-log-type retention policies |

Each ships with documented defaults. The proprietary Data Operations dashboard reads from these to surface "governance posture" — a single-screen view of who owns what, what's classified how, and where access issues exist.

---

## 8.13 What this baseline does NOT cover

Honest scope statement — what an enterprise procurement team should know is **not** in v1:

| Capability | Status |
|---|---|
| SOC 2 / ISO 27001 pack-level certification | Not pursued in v1 |
| End-to-end encryption beyond Snowflake's native | Relies on Snowflake's encryption-at-rest and TLS-in-transit (sufficient for most cases) |
| Customer-managed encryption keys (CMK / BYOK) | Snowflake supports this; pack-level configuration is manual in v1 |
| Real-time DLP scanning | Not in v1; relies on PII tagging and access control |
| Geographic data residency enforcement | Snowflake handles via region selection; pack does not enforce additionally |
| Differential privacy / anonymization beyond hashing | Not in v1 |
| Cross-border data transfer mechanisms (SCCs, BCRs) | Not pack-level; client manages |
| ML-based anomaly detection on access patterns | Not in v1; manual alert thresholds only |

Clients with requirements beyond this baseline are flagged at the implementation engagement and either:
- Receive a custom extension (Spark services)
- Layer their own tooling on top (DLP, encryption gateways, etc.)
- Defer the pack adoption until v2 introduces the missing capability

This honesty matters. A procurement team that discovers a gap mid-deployment loses trust. A procurement team that sees the gap upfront and decides to proceed has bought in with clear eyes.

---

## 8.14 Governance for the AI assistant

The AI assistant (a v2 feature, built on Section 7's semantic layer) introduces governance considerations specific to LLM-mediated access:

| Risk | Mitigation in v2 |
|---|---|
| LLM hallucinates a metric definition | AI assistant only computes via the Semantic Layer API — cannot fabricate SQL |
| LLM returns PII in plaintext | Service account uses `RETAIL_BI_READER`, sees only hashed values |
| LLM logs queries elsewhere | Anthropic API used in zero-data-retention mode; queries are not used for training |
| User asks LLM to bypass restrictions | System prompt instructs refusal; bypass attempts logged |
| LLM is used for unintended purposes | Query rate limiting and usage analytics |

This is mentioned here to set expectations: the AI feature inherits the warehouse's governance posture — it cannot grant access the underlying role doesn't already have. If the AI service account can't see PII, the AI cannot return PII, regardless of how the question is phrased.

---

## 8.15 Governance review checklist for procurement

A checklist a buyer's security team can run against the pack. Each item maps to where in this document it's specified.

| Item | Where addressed |
|---|---|
| Is PII masked by default? | §8.5 ✓ |
| Are masking keys stored securely? | §8.5 (client secret manager) ✓ |
| Is access role-based and least-privilege? | §8.6 ✓ |
| Are access changes logged? | §8.6 ✓ |
| Are PII access queries audited? | §8.5 ✓ |
| Is data classified consistently? | §8.4 ✓ |
| Is every row traceable to its origin? | §8.7 ✓ |
| Is right-to-erasure implemented as code? | §8.10 ✓ |
| Are retention policies configurable? | §8.9 ✓ |
| Is there a quarterly access review process? | §8.6 ✓ |
| Are quality SLAs defined and monitored? | §8.8 ✓ |
| Are domain owners explicitly assigned? | §8.3 ✓ |
| Is consent managed at source? | §8.10 ✓ |
| Are dev/staging/prod environments isolated? | §8.6 ✓ |
| Is the pack auditable for tax / regulatory inquiries? | §8.11 ✓ |
| Are governance artifacts shipped as code/config? | §8.12 ✓ |

Items not on this checklist (SOC 2 cert, real-time DLP, CMK, etc.) are explicitly listed in §8.13 as v1 gaps.

---

## 8.16 Summary

Governance in the Spark Retail Pack is engineered, not improvised. Five principles (§8.2) shape every decision; eight specific subsystems (ownership, classification, PII, access, audit/lineage, quality, retention, erasure) implement them in code.

The pack ships governance as configuration — domain ownership, column classification, retention policies, alert routing, and access matrices all live in YAML files clients edit. No part of the governance baseline requires writing SQL or modifying dbt models.

Most critically, this section is the **single document** a procurement team reviews to understand the pack's governance posture. Other sections are the authoritative source for implementation detail; this section is the synthesis. Where Section 8 conflicts with another section, the other section wins.

The next section (Section 9) defines the synthetic demo data — the realistic, story-driven dataset that makes the pack demonstrable to prospective clients before any real implementation.

---

**Previous:** [Section 7: Semantic Layer](./07_semantic_layer.md)
**Next:** [Section 9: Demo Data Design](./09_demo_data_design.md)
