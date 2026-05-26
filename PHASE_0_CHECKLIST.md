# Phase 0 — Foundation Checklist

> **Phase:** 0 (Foundation)
> **Duration:** Weeks 1–3 of the build roadmap
> **Effort budget:** ~6.5 engineer-weeks (per Section 12.4)
> **Goal:** Snowflake account live, dbt project initialized, CI/CD running, basic source connections established
> **Phase exit gate:** `dbt build` succeeds in CI; all Shopify staging models build green

This checklist sequences Phase 0 work into concrete tasks. Each task references the design section that specifies it. **Check items off as you complete them.** When all are checked, Phase 0 is done.

---

## 0.1 Kickoff decisions (Day 1, before any infrastructure work)

Per Section 13.3, six decisions must be locked before infrastructure provisioning:

- [x] **dbt Cloud vs. dbt Core path** chosen — dbt Core (per ADR-004)
- [x] **Reporting currency** decided — USD (per Section 4 Part 1 §4.11)
- [x] **Reporting timezone** decided — Africa/Nairobi EAT UTC+3 (per Section 4 Part 1 §4.7)
- [x] **Snowflake region** chosen — AWS us-west-2
- [x] **PII handling level** confirmed — full SHA-256 hashing in staging/prod; disabled in dev (per Section 8.5)
- [x] **Retention horizons** confirmed — Section 8.9 defaults, unmodified

Document the decisions in a new file `PHASE_0_DECISIONS.md` at the repo root. These are inputs to multiple subsequent tasks.

---

## 0.2 Snowflake provisioning (Section 2.5, ~1.0 eng-week)

### Account setup
- [x] Snowflake account created in the chosen region — account `RYXGDWD-FPB13834`, region `AWS_US_WEST_2`
- [ ] Multi-factor authentication enabled for the admin account
- [x] Account identifier and credentials securely stored — in `.env` (gitignored); migrate to secrets manager before sharing with team
- [ ] Cost monitoring dashboard configured per Section 4 Part 3 §4.46 — resource monitors created (01-05-2026); Snowsight cost dashboard not yet configured

### Databases
- [x] `RAW_RETAIL` database created (bronze layer)
- [x] `ANALYTICS_RETAIL_DEV` database created (dev environment, masking disabled)
- [x] `ANALYTICS_RETAIL_STAGING` database created (staging environment, masking enabled)
- [x] `ANALYTICS_RETAIL` database created (production environment, masking enabled)
- [ ] Time Travel set to 7 days on `ANALYTICS_RETAIL` per Section 2 §2.9 — not yet verified; check in Snowsight

### Schemas (in each environment database)
- [x] Bronze source schemas in `RAW_RETAIL`: `SHOPIFY`, `STRIPE`, `GA4`, `META_ADS`, `KLAVIYO`
- [x] `STAGING` schema (silver equivalent)
- [x] `GOLD` schema (core dimensions and facts)
- [x] `MART_SALES`, `MART_CUSTOMER`, `MART_INVENTORY` schemas
- [x] `SEMANTIC` schema (materialized semantic layer views — Path 2 of ADR-004)
- [x] `METADATA` schema (audit, lineage, quality logs)
- [x] Additional schemas: `INTERMEDIATE`, `SEEDS`, `SNAPSHOTS`, `QUARANTINE`

### Warehouses
- [x] `WH_LOAD` warehouse (XSmall, auto-suspend 60s) — for ingestion writes
- [x] `WH_TRANSFORM` warehouse (Small or Medium, auto-suspend 60s) — for dbt
- [x] `WH_BI` warehouse (XSmall, auto-suspend 60s) — for Power BI queries
- [x] `WH_ADHOC` warehouse — for analyst ad-hoc queries

### Roles (per Section 2.5 — all 7 roles)
- [x] `RETAIL_LOADER` role created with write access to `RAW_RETAIL`
- [x] `RETAIL_TRANSFORMER` role created with read on `RAW_RETAIL`, write on `ANALYTICS_RETAIL*`
- [x] `RETAIL_BI_READER` role created with read-only on `MART_*` and `SEMANTIC` schemas
- [x] `RETAIL_ANALYST` role created with read on all `ANALYTICS_RETAIL` schemas
- [x] `RETAIL_PII_VIEWER` role created (additive — grants access to `customer_pii_unmasked` mart view)
- [x] `RETAIL_FINANCE_VIEWER` role created (additive — grants access to `confidential`-tagged columns)
- [x] `RETAIL_ADMIN` role created (engineering team only)

### Service accounts
- [x] `SVC_DBT` — dbt service account with `RETAIL_TRANSFORMER` role
- [x] `SVC_INGEST` — ingestion service account with `RETAIL_LOADER` role
- [x] `SVC_POWERBI` — Power BI service account with `RETAIL_BI_READER` role
- [ ] Service account credentials stored in a secrets manager — currently in `.env` only; migrate before onboarding additional team members

---

## 0.3 dbt project scaffolding (Section 4 Part 3, ~1.0 eng-week)

### OSS project (`02_dbt_core/`)
- [x] `dbt_project.yml` created with project name `spark_retail_pack`
- [x] `packages.yml` created — `dbt-labs/dbt_utils`, `dbt-labs/codegen`, `godatadriven/dbt_date`, `dbt-labs/dbt_external_tables` (see notes: `dbt-labs/metrics` removed)
- [x] `profiles.yml.template` created (committed; the real `profiles.yml` is gitignored)
- [x] Folder structure created per CLAUDE.md layout:
  - [x] `models/staging/{shopify,stripe,ga4,meta_ads,klaviyo}/`
  - [x] `models/intermediate/`
  - [x] `models/core/{dimensions,facts}/`
  - [x] `models/marts/{sales,customer,inventory}/`
  - [x] `seeds/source_mappings/`
  - [x] `macros/`
  - [x] `tests/`
  - [x] `snapshots/`
  - [x] `analyses/`
- [x] `.gitkeep` files in empty directories to preserve them in git
- [x] First dbt run succeeds: `dbt deps && dbt parse` — clean (warnings only; expected on empty scaffold)

### Pro project (`03_dbt_pro/`)
- [x] `dbt_project.yml` created with project name `spark_retail_pack_pro`
- [x] `packages.yml` declaring dependency on `spark_retail_pack` via local path (`../02_dbt_core`)
- [x] LICENSE file (commercial license placeholder committed)
- [x] Folder structure:
  - [x] `models/advanced_metrics/`
  - [x] `models/ai_ready/`
  - [x] `models/semantic/` (for MetricFlow YAML per Section 7.4)
  - [x] `macros/`
- [x] First dbt run succeeds: `dbt deps && dbt parse` — clean (warnings only; expected on empty scaffold)

---

## 0.4 CI/CD pipeline (Section 4 Part 3 §4.44, ~1.5 eng-weeks)

- [ ] GitHub Actions (or chosen CI provider) workflow file created
- [ ] CI runs on every PR with these checks:
  - [ ] `dbt deps`
  - [ ] `dbt parse`
  - [ ] `dbt build --select state:modified+` (against a CI-dedicated Snowflake schema)
  - [ ] `dbt test`
  - [ ] SQLFluff linting on changed `.sql` files
  - [ ] YAML schema validation on changed `.yml` files
  - [ ] Python tests for demo generator (when generator exists)
- [ ] CI uses a service account with `RETAIL_TRANSFORMER` role
- [ ] CI secrets configured (Snowflake credentials, dbt Cloud token if used)
- [ ] Branch protection rules on `main`:
  - [ ] Require PR before merge
  - [ ] Require CI to pass
  - [ ] Require at least one review
- [ ] CI failure alerts route to a Slack channel (or equivalent)

---

## 0.5 Source connector configuration (Section 6, ~2.0 eng-weeks)

Configure ingestion for all 5 sources. Use Fivetran, Airbyte, or whichever tool the client uses.

### Shopify (Section 6.4)
- [ ] Shopify connection created in ingestion tool
- [ ] All required tables enabled: `customers`, `orders`, `order_line_items`, `refunds`, `products`, `product_variants`, `inventory_levels`, `inventory_items`, `locations`, `transactions`
- [ ] Initial historical sync completed (typically 2+ years)
- [ ] Sync frequency set to 1–4 hours
- [ ] Data landing in `RAW_RETAIL.SHOPIFY.*` schema

### Stripe (Section 6.5)
- [ ] Stripe connection created
- [ ] Required tables enabled: `customers`, `charges`, `refunds`, `disputes`, `payment_methods`
- [ ] Initial historical sync completed
- [ ] Data landing in `RAW_RETAIL.STRIPE.*`

### Google Analytics 4 (Section 6.6)
- [ ] Path 1 (BigQuery export → ingestion tool) or Path 2 (API connector) chosen
- [ ] GA4 → ingestion → Snowflake path verified
- [ ] Data landing in `RAW_RETAIL.GA4.*`

### Meta Ads (Section 6.7)
- [ ] Meta Ads connection created
- [ ] Required tables enabled: `campaigns`, `ad_sets`, `ads`, `daily_insights`
- [ ] Initial historical sync completed
- [ ] Data landing in `RAW_RETAIL.META_ADS.*`

### Klaviyo (Section 6.8)
- [ ] Klaviyo connection created
- [ ] Required tables enabled: `profiles`, `events`, `campaigns`, `flows`
- [ ] Initial historical sync completed (this is the heaviest — can take 6–12 hours)
- [ ] Data landing in `RAW_RETAIL.KLAVIYO.*`

### Source freshness verification
- [ ] Run `dbt source freshness` after sources are loaded — all 5 sources reporting fresh
- [ ] Freshness thresholds configured per Section 8.8 SLA table

---

## 0.6 Bronze layer (Section 2.2, ~0.5 eng-week)

- [ ] Bronze schemas exist in Snowflake (already done in 0.2)
- [ ] Ingestion tool has write permission only to `RAW_RETAIL` (verified via test write)
- [ ] dbt `sources.yml` files declare all bronze tables for each source
- [ ] Source freshness configured on every source declaration

---

## 0.7 Initial documentation site (~0.5 eng-week)

- [ ] `dbt docs generate` runs successfully (will produce empty docs initially)
- [ ] `dbt docs serve` accessible locally
- [ ] Plan for hosting dbt docs (GitHub Pages, dbt Cloud, custom — decide and stub)
- [ ] README files updated in `02_dbt_core/` and `03_dbt_pro/` to reflect that scaffolding exists

---

## Phase 0 exit gate (per Section 12.10)

Phase 0 is **done** when **all** of these are true:

- [ ] All checkboxes above are checked
- [ ] `dbt build` succeeds in CI on a fresh branch with no model changes (i.e., the scaffolding itself is healthy)
- [ ] All 5 source freshness checks pass
- [ ] At least one team member can deploy a trivial model change end-to-end (PR → CI → merge → CD)

When the gate is met, update the project status to **Phase 1 (Canonical core)** and begin work per Section 12.4 Phase 1.

---

## What NOT to do during Phase 0

Phase 0 is foundational. Resist the temptation to:

- ❌ Start writing staging models (that's Phase 1)
- ❌ Build dimensions or facts (that's Phase 1)
- ❌ Configure Power BI (that's Phase 3)
- ❌ Write the demo data generator (that's Phase 3)
- ❌ Encode semantic layer YAML (that's Phase 2)

Building these before the foundation is solid creates rework. The build roadmap (Section 12) is sequenced deliberately.

---

## Notes log

Use this space to track decisions, issues, and learnings during Phase 0. Capture anything that might inform an ADR or a documentation update.

### Decisions made

**2026-05-26 — Role hierarchy: no `SYSADMIN → RETAIL_ADMIN` grant**
The original `03_roles.sql` attempted both `GRANT ROLE RETAIL_ADMIN TO SYSADMIN` and `GRANT ROLE SYSADMIN TO RETAIL_ADMIN`. Snowflake rejects this as a cycle. Decision: all 7 custom roles are granted up to `SYSADMIN` (so any SYSADMIN user can assume them), and `SYSADMIN` is NOT granted down to `RETAIL_ADMIN`. Engineers who need warehouse-admin capability are granted `SYSADMIN` directly on their user account in Snowsight — not via the role hierarchy.

**2026-05-26 — `dbt-labs/metrics` removed from packages.yml**
MetricFlow is built into dbt Core 1.6+ and the `dbt-labs/metrics` package was deprecated. Removed from `02_dbt_core/packages.yml`. Semantic layer models live in `03_dbt_pro/models/semantic/` as intended.

**2026-05-26 — `calogica/dbt_date` renamed to `godatadriven/dbt_date`**
The `calogica/dbt_date` package was deprecated; replaced with `godatadriven/dbt_date` at the same version (0.10.1). No API changes.

**2026-05-26 — `tests:` renamed to `data_tests:` in dbt_project.yml**
dbt 1.8 renamed the `tests:` key in `dbt_project.yml` to `data_tests:`. Updated OSS project accordingly. Pro project has no test config so no change needed there.

**2026-05-26 — PII hash salt generated and stored in `.env`**
Salt: `c19288b15753a0db947d1074c98030e0dc0089cbcd33107c6bc0c1c8ad95284c`. This value must be consistent across all environments that need comparable hashes. Store in secrets manager before sharing with team or running in CI.

### Issues encountered

**2026-05-26 — Circular role grant in `03_roles.sql`**
`GRANT ROLE SYSADMIN TO RETAIL_ADMIN` failed because the prior statement had already granted `RETAIL_ADMIN` to `SYSADMIN`. Fixed by removing the downward grant. See decision above.

### Candidate ADRs

_(Add as Phase 0 progresses — design gaps that need formal decisions)_
