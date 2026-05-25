# Section 4 — Part 3: Implementation Standards and Best Practices

> **Document status:** Draft v1
> **Audience:** Engineering team, contributors, technical implementation partners
> **Purpose:** Define the engineering disciplines that turn the canonical data model from "thoughtful blueprint" into "production-ready specification." This part covers how the model is built, tested, materialized, versioned, evolved, and operated — not what columns it contains.

---

## 4.33 Why this Part exists

Parts 1 and 2 of Section 4 define **what** the canonical model contains: dimensions, facts, columns, types, audit footers. They are necessary but not sufficient. A production-grade data warehouse also requires explicit standards for:

- How models are tested
- How they are materialized in Snowflake
- How incremental loads handle late-arriving data
- How SCD2 snapshots are captured
- How sources are version-pinned
- How errors are surfaced
- How schemas evolve safely

Without these, two implementations of the same canonical model will behave differently in production, and clients will lose trust in the pack.

These standards are deliberately separated from Parts 1 and 2 because they describe **operational behavior**, not data structure. The two should be readable independently.

---

## 4.34 Materialization strategy by layer

dbt offers four core materializations: `view`, `table`, `incremental`, and `ephemeral`. The pack uses each deliberately, by layer.

| Layer | Default materialization | Reason |
|---|---|---|
| Sources (bronze) | (Not dbt-managed) | Loaded by ingestion tool — Fivetran, Airbyte, etc. |
| Staging | `view` | Lightweight; runs on demand; no storage cost |
| Intermediate | `ephemeral` | CTEs inlined into downstream models; not materialized |
| Core dimensions (Type 1) | `table` | Full rebuild on each run; small tables |
| Core dimensions (Type 2 / SCD2) | `snapshot` | Captures changes over time via dbt snapshots |
| Core facts (low volume, < 1M rows/year) | `table` | Full rebuild; cheaper than incremental complexity |
| Core facts (high volume) | `incremental` | Append-only loads on new partitions |
| Marts | `table` | Pre-aggregated, often joined; rebuilt on demand |
| Semantic layer outputs | `view` | Defined in MetricFlow; not materialized as tables |

### Per-fact materialization table

| Fact | Materialization | Reason |
|---|---|---|
| `fact_orders` | `incremental` (merge) | Volume + late-arriving refunds modify existing rows |
| `fact_order_lines` | `incremental` (merge) | Volume + late updates from refunds |
| `fact_refunds` | `incremental` (append) | Append-only events |
| `fact_marketing_spend` | `incremental` (merge) | Daily updates to recent dates |
| `fact_web_sessions` | `incremental` (append) | High volume, append-only |
| `fact_email_engagement` | `incremental` (append) | High volume, append-only |
| `fact_customer_state_daily` | `incremental` (merge) | Snapshot fact, idempotent per `snapshot_date` |
| `fact_inventory_snapshot` | `incremental` (merge) | Snapshot fact, idempotent per `snapshot_date` |
| `fact_inventory_movements` | `incremental` (append) | Append-only events |

Materialization is declared in `dbt_project.yml` at the folder level, with per-model overrides where needed:

```yaml
models:
  spark_retail_pack:
    staging:
      +materialized: view
    intermediate:
      +materialized: ephemeral
    core:
      +materialized: table
      facts:
        +materialized: incremental
        fact_orders:
          +incremental_strategy: merge
          +unique_key: order_id
    marts:
      +materialized: table
```

---

## 4.35 Incremental load strategy

For every incremental fact, the following must be explicitly defined:

| Property | Value (default) |
|---|---|
| `incremental_strategy` | `merge` for facts that update; `append` for append-only events |
| `unique_key` | The natural key (never the surrogate); enables idempotent re-runs |
| `on_schema_change` | `append_new_columns` — adds new columns without breaking the load |
| `lookback_window` | How far back from the latest load to re-scan (default: 7 days) |

### Lookback window pattern

Pure incremental loads that only pull "data newer than the latest row" miss late-arriving records. A real-world example: an order placed on Day 1 may be refunded on Day 8; if the load on Day 8 only pulls events from Day 8, the refund updates the wrong way.

The pack uses a **lookback window**: each incremental run re-pulls the trailing N days from source, not just the latest. This catches late-arriving updates without re-pulling the entire fact.

```sql
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='order_id',
    on_schema_change='append_new_columns'
) }}

select * from {{ ref('stg_shopify__orders') }}

{% if is_incremental() %}
  where updated_at >= (
      select dateadd('day', -{{ var('incremental_lookback_days', 7) }}, max(updated_at))
      from {{ this }}
  )
{% endif %}
```

Default lookback windows by fact:

| Fact | Lookback | Reason |
|---|---|---|
| `fact_orders` | 14 days | Refunds, fulfillment updates often within 2 weeks |
| `fact_order_lines` | 14 days | Same as orders |
| `fact_refunds` | 30 days | Chargebacks can arrive weeks late |
| `fact_marketing_spend` | 7 days | Platforms occasionally adjust spend within attribution windows |
| `fact_web_sessions` | 3 days | Sessions are typically settled within hours |
| `fact_email_engagement` | 3 days | Mostly real-time |
| `fact_inventory_movements` | 7 days | Manual adjustments may be back-dated |

Lookback windows are configurable per client via `vars.incremental_lookback_<fact_name>_days`.

### Full refresh trigger

Every incremental model supports a `--full-refresh` flag for cases where the table must be rebuilt from scratch (schema change, data correction, initial backfill). The pack documents which scenarios require full refresh in `docs/operational_runbook.md`.

---

## 4.36 SCD2 snapshot strategy

The SCD2 dimensions (`dim_customer`, `dim_product`, `dim_marketing_campaign`) are implemented using **dbt snapshots** against the staging layer.

### Snapshot configuration

```sql
{% snapshot snap_customer %}

{{
    config(
      target_schema='snapshots',
      strategy='check',
      unique_key='customer_id',
      check_cols=['email_hash', 'phone_hash', 'customer_status',
                  'country_code', 'marketing_consent', 'customer_segment'],
      invalidate_hard_deletes=False
    )
}}

select * from {{ ref('int_customer_identity_resolution') }}

{% endsnapshot %}
```

### Strategy choice: `check` vs. `timestamp`

| Strategy | When to use | Pack default |
|---|---|---|
| `timestamp` | Source has a reliable `updated_at` column on every row | Used for `dim_product` (Shopify provides `updated_at`) |
| `check` | Source's `updated_at` is unreliable or not present on all changes | Used for `dim_customer` (multiple sources, inconsistent timestamps) |

### Soft-delete handling

`invalidate_hard_deletes` is **always set to FALSE** in the pack. Reason: hard-deleted source records destroy analytical history. A customer who deletes their account should still appear in historical reports — flagged via `_is_deleted_at_source = TRUE`, not removed.

### Snapshot orchestration

Snapshots run **before** the rest of the dbt build, not after. The DAG is:

```
1. dbt source freshness    (verify sources are fresh)
2. dbt snapshot             (capture current state of SCD2 dimensions)
3. dbt run                  (build staging → intermediate → core → marts)
4. dbt test                 (validate)
5. dbt docs generate        (refresh documentation)
```

This ordering ensures the day's transformations see the most current snapshot of dimensional history.

---

## 4.37 Testing strategy

Every model in the pack has tests defined in a sibling `schema.yml` file. Tests fall into four categories.

### Category 1: Schema tests (required on every model)

Tests that come for free with dbt and run on every column where applicable:

| Test | Applied to | Frequency |
|---|---|---|
| `not_null` | All non-nullable columns | Every model |
| `unique` | All natural and surrogate keys | Every dimension and fact |
| `accepted_values` | All enum-like columns (`order_status`, `customer_status`, etc.) | Every model with enums |
| `relationships` | All foreign keys to dimensions | Every fact |
| `dbt_utils.expression_is_true` | Computed columns (e.g., `net_amount = gross - discount + tax + shipping`) | Every fact with computed columns |

### Category 2: Business rule tests (required where applicable)

Custom tests that enforce business rules:

```yaml
# models/core/schema.yml
- name: fact_orders
  tests:
    - dbt_utils.expression_is_true:
        expression: "net_amount >= 0"
        config:
          severity: warn
    - dbt_utils.expression_is_true:
        expression: "refunded_amount <= net_amount"
        config:
          severity: error
    - dbt_utils.recency:
        datepart: day
        field: order_date
        interval: 2
```

### Category 3: Source freshness tests (required on every source)

Every source table has freshness expectations:

```yaml
# models/staging/shopify/_shopify__sources.yml
sources:
  - name: shopify
    freshness:
      warn_after: {count: 6, period: hour}
      error_after: {count: 24, period: hour}
    loaded_at_field: _extracted_at
    tables:
      - name: orders
      - name: customers
      - name: products
```

Source freshness SLAs by source:

| Source | Warn after | Error after |
|---|---|---|
| Shopify | 6 hours | 24 hours |
| Stripe | 6 hours | 24 hours |
| GA4 | 12 hours | 48 hours (GA4 has its own latency) |
| Meta Ads | 12 hours | 48 hours |
| Klaviyo | 6 hours | 24 hours |

### Category 4: Singular tests (model-specific)

SQL files in `tests/` directory that encode complex business rules:

```sql
-- tests/no_orders_without_lines.sql
select o.order_id
from {{ ref('fact_orders') }} o
left join {{ ref('fact_order_lines') }} l on o.order_sk = l.order_sk
where l.line_item_sk is null
  and o.line_item_count > 0
```

### Test severity policy

| Severity | When to use |
|---|---|
| `error` | Failing this test means data is wrong and should not be trusted. Pipeline halts. |
| `warn` | Failing this test is concerning but data is usable. Pipeline continues; alert raised. |

The pack's default is `error` for: schema tests on keys, relationships tests, source freshness `error_after` thresholds.

The pack's default is `warn` for: business rule violations that may be legitimate edge cases (e.g., negative line items for adjustments), recency tests in dev environments.

### Test naming convention

Tests should be named so failures are self-explanatory:

```yaml
- name: customer_id
  tests:
    - not_null:
        config:
          alias: dim_customer_customer_id_not_null
    - unique:
        config:
          alias: dim_customer_customer_id_unique
```

Failed test output then reads `FAIL dim_customer_customer_id_unique` instead of `FAIL unique_dim_customer_customer_id`.

---

## 4.38 Schema evolution and source changes

Source systems change. Shopify adds a column to `orders`. Meta Ads renames a field. The pack must handle this without breaking existing client deployments.

### Three categories of schema change

| Change | Example | Pack response |
|---|---|---|
| **Additive — new column added to source** | Shopify adds `delivery_method_id` to orders | Auto-included if `on_schema_change: append_new_columns` set. Not consumed in canonical model until explicitly added. Documented in changelog. |
| **Non-breaking — column renamed at source** | Shopify renames `total_price` to `current_total_price` | Staging model handles the rename in the source mapping seed. Canonical model unaffected. |
| **Breaking — column removed or type changed at source** | Shopify removes `tax_amount` and replaces with `tax_lines[]` | Pack version bump required. Migration documented. Old version supported in parallel for 6 months. |

### Semantic versioning of the pack

The pack follows semantic versioning (`MAJOR.MINOR.PATCH`):

- **PATCH** (e.g., 1.2.3 → 1.2.4): Bug fixes, performance improvements, documentation. No schema changes. Clients can upgrade without coordination.
- **MINOR** (e.g., 1.2.x → 1.3.0): New columns added to canonical model, new dimensions or facts added, new KPIs added. Backwards-compatible. Clients can upgrade with minimal coordination.
- **MAJOR** (e.g., 1.x.x → 2.0.0): Breaking changes to canonical model — column removed, semantics changed, fact restructured. Requires migration. Old version supported in parallel for 6 months minimum.

The version is declared in `dbt_project.yml` and surfaced in the warehouse via `metadata.pack_version` table.

### Source contract enforcement

Each connector specification (Section 6) declares the **minimum source contract** — columns the staging models depend on. If a source no longer provides one of these, the build fails fast at the staging layer with a clear error.

```yaml
# models/staging/shopify/_shopify__sources.yml
sources:
  - name: shopify
    tables:
      - name: orders
        columns:
          - name: id
            tests: [not_null, unique]
          - name: created_at
            tests: [not_null]
          - name: total_price
            tests: [not_null]
```

If Shopify's `total_price` disappears or starts arriving null, `dbt test` fails before any downstream model runs.

---

## 4.39 Hard-delete vs. soft-delete handling

Sources handle deletes differently. The pack's policy:

| Source behavior | Pack response |
|---|---|
| Source soft-deletes (sets `deleted_at` or similar flag) | Capture as `_is_deleted_at_source = TRUE`. Retain row in warehouse. Downstream models filter as appropriate. |
| Source hard-deletes (row vanishes from source) | Compare current source set to warehouse on each run. Rows missing from source are flagged `_is_deleted_at_source = TRUE` in the next snapshot. Original row is retained. |
| Source provides no delete signal | Trust the source: assume any row that hasn't been updated in N months is deleted. (N is configurable per source, default 24 months.) |

The principle: **the warehouse never loses history, even when the source does.** This is what makes the warehouse the system of record for analytics.

Clients with strict regulatory deletion requirements (GDPR right-to-erasure, CCPA opt-out) use the dedicated customer-erasure macro (Section 4.41) — not source-driven deletes.

---

## 4.40 Backfill and replay strategy

Three scenarios require rebuilding data:

### Scenario 1: Initial load (first deployment)

A new client onboards. Their Shopify history goes back 3 years. The pack must:

1. Load all historical source data via the ingestion tool (one-time backfill, typically 1–4 hours).
2. Run `dbt build --full-refresh` to populate the entire canonical model from scratch.
3. Generate `fact_customer_state_daily` and `fact_inventory_snapshot` retroactively — daily snapshots back-filled for the retention horizon (24 months by default).

The retroactive snapshot generation is the most expensive step. The pack ships a `models/intermediate/int_backfill_customer_state.sql` model that synthesizes daily snapshots from the order history at one-shot. Initial backfill: 30–90 minutes depending on volume.

### Scenario 2: Source replay (source data corrected)

A source provider (e.g., Shopify) issues a data correction or the ingestion tool replays. The pack must:

1. Re-run ingestion into bronze (handled by the ingestion tool).
2. Run `dbt build --select +fact_orders+ --full-refresh` to rebuild affected fact tables and their downstream dependents.
3. Verify with `dbt test`.

### Scenario 3: Pack version upgrade

Client upgrades from pack v1.2 to v1.3 (new columns added):

1. Pull new pack version.
2. Run `dbt run --select state:modified+ --state ./previous_run` — only rebuilds models that changed.
3. Run `dbt test` against new schema.

For major version upgrades (1.x → 2.x), the pack ships migration scripts in `migrations/v1_to_v2/`.

---

## 4.41 Privacy and right-to-erasure

Per GDPR Article 17 and CCPA equivalents, customers have the right to have their data erased. The pack handles this via a dedicated macro pattern, not source-driven deletion.

### The erasure flow

1. Client receives an erasure request, validates identity, records in their compliance system.
2. Client adds the customer's `customer_id` to `seeds/erasure_requests.csv`:

   ```csv
   customer_id, request_date, ticket_id, scope
   abc123, 2026-04-15, GDPR-7421, full_erasure
   def456, 2026-04-20, CCPA-2289, marketing_only
   ```

3. The `customer_erasure` macro runs on the next dbt build:

   - For `full_erasure`: replaces all PII fields with hashed placeholders across `dim_customer`, `fact_orders`, `fact_web_sessions`, `fact_email_engagement`. Customer remains in the warehouse for analytical integrity (with no identifying info).
   - For `marketing_only`: sets `marketing_consent = FALSE`, `email_subscribed = FALSE`, `sms_subscribed = FALSE`. Removes from active marketing audiences.

4. The erasure is logged in `metadata.erasure_log` for audit.

### Why analytical retention is preserved

Erasure does not mean "row vanishes." A customer who placed 50 orders contributes to revenue, cohort, and inventory analytics regardless of their identity. The pack preserves the order events themselves (with PII stripped) so analytical history remains intact while individual identification is destroyed.

This pattern is the industry standard for analytics warehouses post-GDPR. Clients in regulated industries should review with counsel and may need to override the default behavior.

---

## 4.42 Error handling and alerting

When the pipeline fails, three things must happen: the failure must be visible, recoverable, and not silently propagate bad data downstream.

### Failure modes and responses

| Failure mode | Response |
|---|---|
| Source freshness warn threshold breached | Slack alert (channel `#data-warnings`); pipeline continues |
| Source freshness error threshold breached | Slack alert (channel `#data-incidents`); pipeline halts before that source's models |
| dbt model fails to build | Slack alert; pipeline halts; downstream models skipped |
| dbt test fails with severity=error | Slack alert; pipeline halts; downstream models skipped |
| dbt test fails with severity=warn | Slack alert (low priority); pipeline continues |
| Snowflake query exceeds 60-minute timeout | Slack alert; query killed; pipeline marked failed |
| dbt run exceeds 4-hour total runtime | Slack alert; runtime warning; investigate next run |

### Alerting channels

The pack ships configurable alerting via:

- **Slack** (default — webhook URL configured in env vars)
- **Email** (SMTP or SES)
- **PagerDuty** (for clients with on-call rotations)
- **dbt Cloud notifications** (if running on dbt Cloud)

### Retry policy

| Failure type | Auto-retry |
|---|---|
| Transient Snowflake error (network, deadlock) | Yes — up to 3 retries with exponential backoff |
| Schema/test failure | No — requires human intervention |
| Resource exhaustion (warehouse too small) | No — alerts for capacity review |

### Quarantine pattern for bad data

When a test fails on a small subset of rows but the bulk of the data is fine, the pack supports a **quarantine pattern**: failed rows are diverted to a `quarantine_<model>` table for review, and the main model continues with the valid subset.

```sql
{{ config(
    materialized='incremental',
    on_schema_change='append_new_columns',
    post_hook="{{ quarantine_failed_rows('fact_orders', 'order_id', 'net_amount >= 0') }}"
) }}
```

This is opt-in per model. Default behavior is "halt on failure."

---

## 4.43 Environment strategy

Three environments are standard:

| Environment | Snowflake database | Purpose | Refresh frequency |
|---|---|---|---|
| `dev` | `ANALYTICS_RETAIL_DEV` | Analytics engineer sandbox; per-developer schemas | On-demand |
| `staging` | `ANALYTICS_RETAIL_STAGING` | Integration testing; mirrors prod schema | Daily |
| `prod` | `ANALYTICS_RETAIL` | Production analytics | Per schedule (typically hourly or daily) |

### Per-environment overrides

dbt's `target` mechanism handles environment-specific config:

```yaml
# profiles.yml (client-managed)
spark_retail_pack:
  target: dev
  outputs:
    dev:
      type: snowflake
      database: ANALYTICS_RETAIL_DEV
      schema: "{{ env_var('DBT_USER_SCHEMA') }}"  # per-developer
      warehouse: WH_DEV_TRANSFORM
    staging:
      type: snowflake
      database: ANALYTICS_RETAIL_STAGING
      schema: ANALYTICS
      warehouse: WH_TRANSFORM
    prod:
      type: snowflake
      database: ANALYTICS_RETAIL
      schema: ANALYTICS
      warehouse: WH_TRANSFORM
```

### PII handling per environment

- **Dev:** PII masking disabled (`vars.pii_masking_enabled = false`); only synthetic data
- **Staging:** PII masking enabled; access restricted to engineering team
- **Prod:** PII masking enabled; standard role-based access

### Promotion flow

Changes flow `dev → staging → prod` via Git:

1. Engineer develops in dev branch, runs against their dev schema.
2. PR opened against `main` branch. CI runs tests against staging.
3. PR merged. Staging deploys automatically.
4. After staging validation (24 hours minimum), production tag created and deployed.

---

## 4.44 CI/CD pipeline

For the open-source pack, GitHub Actions is the default CI provider. Clients can use any equivalent (GitLab CI, CircleCI, etc.).

### CI pipeline stages

```yaml
# .github/workflows/dbt-ci.yml
name: dbt CI

on: [pull_request]

jobs:
  dbt-build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Python and dbt
        run: |
          pip install dbt-snowflake==1.8.0
          dbt deps
      - name: Run dbt build on modified models
        run: |
          dbt build --select state:modified+ --defer --state ./prod-manifest
      - name: Run dbt tests
        run: |
          dbt test --select state:modified+
      - name: Check for documentation
        run: |
          dbt docs generate
          python scripts/check_undocumented_columns.py
```

### Required checks before merge

- All `dbt build` steps pass on modified models
- All `dbt test` checks pass (severity=error)
- All new columns have descriptions in `schema.yml`
- No models lack a description
- No SQL files exceed 500 lines (forces decomposition)
- Linter (`sqlfluff`) passes

### State-based runs

`dbt build --select state:modified+` runs only the modified models and their downstream dependents, rather than the entire DAG. This keeps CI fast (typically <5 minutes for normal changes).

---

## 4.45 Documentation discipline

Every model and column has a description. This is enforced by CI.

### Documentation pattern

```yaml
# models/core/_core__models.yml
version: 2
models:
  - name: dim_customer
    description: |
      Single record per customer per version. Customers are identity-resolved
      across Shopify, Stripe, and Klaviyo via email hash (primary), phone hash
      (secondary), and fuzzy name+address match (tertiary). SCD2 captures
      attribute changes over time.
    columns:
      - name: customer_sk
        description: Surrogate key. MD5 hash of customer_id and valid_from.
        tests: [not_null, unique]
      - name: customer_id
        description: |
          Canonical business key, stable across versions. Hash of
          lowercased primary email.
        tests: [not_null]
      - name: email_hash
        description: SHA-256 hash of normalized email. Used for joins.
        tests: [not_null]
```

### Documentation enforcement

A pre-commit hook and CI step check:

- Every model has a description
- Every column has a description
- Every test has a meaningful name or description
- All `dbt_utils.expression_is_true` tests have a comment explaining what they enforce

Failing any of these blocks the PR.

### Per-source documentation

Every source connector has a dedicated README explaining:

- Which source tables are required vs. optional
- Expected schema and field semantics
- Known edge cases (e.g., "Shopify omits `tax_amount` for tax-exempt orders")
- Ingestion tool configuration (Fivetran sync mode, etc.)

Located in `docs/connectors/<source>.md`. Detailed connector specs in Section 6.

---

## 4.46 Cost monitoring and query optimization

Snowflake compute costs scale with query complexity and warehouse size. Without monitoring, a single bad query can cost hundreds of dollars.

### Monitoring approach

The pack writes per-query cost data to `metadata.query_cost_log` daily, sourced from Snowflake's `ACCOUNT_USAGE.QUERY_HISTORY`:

| Column | Description |
|---|---|
| `query_id` | Snowflake query ID |
| `dbt_model` | Producing dbt model (from `_dbt_model` column) |
| `dbt_invocation_id` | Producing dbt run |
| `warehouse_size` | Warehouse used |
| `execution_time_ms` | Time |
| `bytes_scanned` | Data scanned |
| `credits_used` | Snowflake credits consumed |

A daily aggregation produces a "top 10 most expensive models" report, surfaced in the proprietary Data Operations dashboard.

### Cost-control defaults

| Setting | Default | Purpose |
|---|---|---|
| Warehouse auto-suspend | 60 seconds | Stops compute when idle |
| Warehouse auto-resume | Enabled | Compute spins back up on demand |
| Statement timeout | 60 minutes | Kills runaway queries |
| Max concurrency level per warehouse | 8 | Prevents thrashing |
| dbt threads | 4 (dev), 8 (prod) | Balances speed and warehouse load |

### Query optimization patterns

The pack follows these for high-volume facts:

- **Cluster by partition column + most-filtered dimension** (documented in Section 4.28)
- **Avoid `SELECT *` in production models** — explicit column lists only
- **Use `QUALIFY` for window-function deduplication** (Snowflake-specific, faster than CTEs)
- **Use `LATERAL FLATTEN` for arrays, not `LISTAGG` reverse-parsing**
- **Materialize intermediate aggregations as tables** when the same aggregation is used by 3+ downstream models

---

## 4.47 Macro library inventory

A consolidated reference of every macro in the pack, with location and purpose.

### Open-source macros (in `spark_retail_pack`)

| Macro | Location | Purpose |
|---|---|---|
| `add_audit_columns` | `macros/audit/` | Adds the 8-column audit footer (Section 4.31) |
| `generate_dim_sk` | `macros/keys/` | Generates surrogate keys (with or without SCD2 timestamp) |
| `apply_source_mapping` | `macros/source_mapping/` | Reads YAML mapping config and applies it in staging |
| `pii_mask` | `macros/pii/` | Hashes or masks PII based on environment config |
| `quarantine_failed_rows` | `macros/quality/` | Post-hook that diverts failed rows to quarantine tables |
| `customer_erasure` | `macros/privacy/` | Applies GDPR/CCPA erasure across affected tables |
| `daily_fx_rate` | `macros/currency/` | Looks up daily FX rate for currency conversion |
| `incremental_lookback` | `macros/incremental/` | Returns the lookback window cutoff for incremental loads |
| `lineage_edges` | `macros/metadata/` | Generates the lineage helper view |

### Proprietary macros (in `spark_retail_pack_pro`)

| Macro | Location | Purpose |
|---|---|---|
| `rfm_tier_calculation` | `macros/segmentation/` | Computes RFM tiers per customer |
| `cohort_retention_matrix` | `macros/customer/` | Builds the cohort retention matrix |
| `attribution_first_touch` | `macros/attribution/` | First-touch attribution for marketing spend |
| `attribution_last_touch` | `macros/attribution/` | Last-touch attribution |
| `predict_churn_risk` | `macros/ml/` | Applies pre-trained churn model |
| `inventory_velocity_flags` | `macros/inventory/` | Computes overstock, slow-mover, and at-risk flags |

Every macro has:

- A docstring explaining purpose, inputs, outputs
- Example usage in the macro file header
- Unit test in `tests/macros/`

---

## 4.48 Dependency version pinning

dbt and its packages must be pinned to specific versions to avoid "works on my machine" failures.

### Pinned versions (as of pack v1.0)

```yaml
# packages.yml
packages:
  - package: dbt-labs/dbt_utils
    version: 1.3.0
  - package: dbt-labs/codegen
    version: 0.13.1
  - package: calogica/dbt_date
    version: 0.10.1
  - package: dbt-labs/dbt_external_tables
    version: 0.10.1
  - package: dbt-labs/metrics
    version: 1.7.5
```

```toml
# requirements.txt (Python dependencies)
dbt-core==1.8.0
dbt-snowflake==1.8.0
sqlfluff==3.0.7
sqlfluff-templater-dbt==3.0.7
pre-commit==3.7.0
```

### Upgrade cadence

- **Patch versions** auto-upgraded monthly via Dependabot
- **Minor versions** reviewed quarterly; manual upgrade after staging validation
- **Major versions** treated as breaking changes; full regression testing required

---

## 4.49 Exposures

dbt's `exposures` feature declares downstream consumers of warehouse models. The pack defines the standard exposures every implementation will have.

```yaml
# models/exposures.yml
version: 2
exposures:
  - name: executive_summary_dashboard
    type: dashboard
    maturity: high
    owner:
      name: Spark Retail Pack
      email: support@sparkanalytics.example
    depends_on:
      - ref('mart_sales.sales_daily_summary')
      - ref('mart_sales.sales_top_products')
      - metric('net_revenue')
      - metric('average_order_value')
    description: |
      Power BI Executive Summary dashboard. Pulls daily revenue, top products,
      and channel breakdowns.
```

Exposures provide:

- A visible link between warehouse models and business consumers
- Lineage that extends beyond dbt (into Power BI, ML models, etc.)
- A "what would break if I changed this model?" check

The pack ships exposures for each of the three Power BI dashboards, and clients add their own.

---

## 4.50 Operational runbook reference

A separate `docs/operational_runbook.md` ships with the pack and covers:

- How to do a full refresh
- How to roll back a bad deployment
- How to investigate a failed test
- How to add a new client-specific dimension
- How to upgrade pack versions
- Common Snowflake errors and resolutions
- Performance tuning guidance
- Contact information for support escalation

This runbook is not in the design doc because it's operational — it lives with the code. Mentioned here so that future contributors know where it is.

---

## 4.51 Summary of standards

Recap of the disciplines this Part establishes:

| Discipline | Where defined | Enforcement |
|---|---|---|
| Materialization strategy | Section 4.34 | `dbt_project.yml` |
| Incremental loads | Section 4.35 | Per-model config |
| SCD2 snapshots | Section 4.36 | Snapshot files |
| Testing | Section 4.37 | `schema.yml` + CI |
| Schema evolution | Section 4.38 | Source contracts + semver |
| Delete handling | Section 4.39 | Macro pattern |
| Backfill | Section 4.40 | Documented procedures |
| Privacy / erasure | Section 4.41 | Erasure macro |
| Error handling | Section 4.42 | Alerting + retry config |
| Environments | Section 4.43 | `profiles.yml` |
| CI/CD | Section 4.44 | GitHub Actions |
| Documentation | Section 4.45 | CI checks |
| Cost monitoring | Section 4.46 | Query log + dashboard |
| Macro inventory | Section 4.47 | Documented in each file |
| Dependency pinning | Section 4.48 | `packages.yml`, `requirements.txt` |
| Exposures | Section 4.49 | `exposures.yml` |

Together with Parts 1 and 2, these define the **canonical data model as a production-ready specification** — not just a schema design.

---

**Previous:** [Section 4 — Part 2: Canonical Data Model — Facts](./04_canonical_data_model_part2_facts.md)
**Next:** [Section 5: KPI Catalog](./05_kpi_catalog.md)
