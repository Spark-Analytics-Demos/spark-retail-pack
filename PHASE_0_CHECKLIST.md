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

- [ ] **dbt Cloud vs. dbt Core path** chosen (per ADR-004). For internal v1 build, recommendation is dbt Core to start; layer dbt Cloud later if needed.
- [ ] **Reporting currency** decided (default: USD; per Section 4 Part 1 §4.11)
- [ ] **Reporting timezone** decided (default: client HQ timezone; per Section 4 Part 1 §4.7)
- [ ] **Snowflake region** chosen (default: `us-east-1` for US; `eu-west-1` for EU)
- [ ] **PII handling level** confirmed (default: full hashing in non-dev environments; per Section 8.5)
- [ ] **Retention horizons** confirmed (Section 8.9 defaults unless modified)

Document the decisions in a new file `PHASE_0_DECISIONS.md` at the repo root. These are inputs to multiple subsequent tasks.

---

## 0.2 Snowflake provisioning (Section 2.5, ~1.0 eng-week)

### Account setup
- [ ] Snowflake account created in the chosen region (Standard or Enterprise edition)
- [ ] Multi-factor authentication enabled for the admin account
- [ ] Account identifier and credentials securely stored (not in this repo)
- [ ] Cost monitoring dashboard configured per Section 4 Part 3 §4.46

### Databases
- [ ] `RAW_RETAIL` database created (bronze layer)
- [ ] `ANALYTICS_RETAIL_DEV` database created (dev environment, masking disabled)
- [ ] `ANALYTICS_RETAIL_STAGING` database created (staging environment, masking enabled)
- [ ] `ANALYTICS_RETAIL` database created (production environment, masking enabled)
- [ ] Time Travel set to 7 days on `ANALYTICS_RETAIL` per Section 2 §2.9

### Schemas (in each environment database)
- [ ] `BRONZE` schema (raw landed data per source)
- [ ] `SILVER` schema (staging)
- [ ] `GOLD` schema (core dimensions and facts)
- [ ] `MART_SALES`, `MART_CUSTOMER`, `MART_INVENTORY` schemas
- [ ] `SEMANTIC` schema (materialized semantic layer views — Path 2 of ADR-004)
- [ ] `METADATA` schema (audit, lineage, quality logs)

### Warehouses
- [ ] `WH_LOAD` warehouse (XSmall, auto-suspend 60s) — for ingestion writes
- [ ] `WH_TRANSFORM` warehouse (Small or Medium, auto-suspend 60s) — for dbt
- [ ] `WH_BI` warehouse (XSmall, auto-suspend 60s) — for Power BI queries

### Roles (per Section 2.5 — all 7 roles)
- [ ] `RETAIL_LOADER` role created with write access to `RAW_RETAIL`
- [ ] `RETAIL_TRANSFORMER` role created with read on `RAW_RETAIL`, write on `ANALYTICS_RETAIL*`
- [ ] `RETAIL_BI_READER` role created with read-only on `MART_*` and `SEMANTIC` schemas
- [ ] `RETAIL_ANALYST` role created with read on all `ANALYTICS_RETAIL` schemas
- [ ] `RETAIL_PII_VIEWER` role created (additive — grants access to `customer_pii_unmasked` mart view)
- [ ] `RETAIL_FINANCE_VIEWER` role created (additive — grants access to `confidential`-tagged columns)
- [ ] `RETAIL_ADMIN` role created (engineering team only)

### Service accounts
- [ ] Service account for dbt with `RETAIL_TRANSFORMER` role
- [ ] Service account for ingestion tool with `RETAIL_LOADER` role
- [ ] Service account for Power BI with `RETAIL_BI_READER` role
- [ ] All service account credentials stored in a secrets manager (NOT in repo)

---

## 0.3 dbt project scaffolding (Section 4 Part 3, ~1.0 eng-week)

### OSS project (`02_dbt_core/`)
- [ ] `dbt_project.yml` created with project name `spark_retail_pack`
- [ ] `packages.yml` created with `dbt-labs/dbt_utils` and `dbt-labs/metrics` pinned per Section 7.3
- [ ] `profiles.yml.template` created (committed; the real `profiles.yml` is gitignored)
- [ ] Folder structure created per CLAUDE.md layout:
  - [ ] `models/staging/{shopify,stripe,ga4,meta_ads,klaviyo}/`
  - [ ] `models/intermediate/`
  - [ ] `models/core/{dimensions,facts}/`
  - [ ] `models/marts/{sales,customer,inventory}/`
  - [ ] `seeds/source_mappings/`
  - [ ] `macros/`
  - [ ] `tests/`
  - [ ] `snapshots/`
  - [ ] `analyses/`
- [ ] `.gitkeep` files in empty directories to preserve them in git
- [ ] First dbt run succeeds: `dbt deps && dbt parse`

### Pro project (`03_dbt_pro/`)
- [ ] `dbt_project.yml` created with project name `spark_retail_pack_pro`
- [ ] `packages.yml` declaring dependency on `spark_retail_pack` (the OSS package)
- [ ] LICENSE file (commercial license terms, even if not yet finalized — placeholder OK)
- [ ] Folder structure:
  - [ ] `models/advanced_metrics/`
  - [ ] `models/ai_ready/`
  - [ ] `models/semantic/` (for MetricFlow YAML per Section 7.4)
  - [ ] `macros/`
- [ ] First dbt run succeeds: `dbt deps && dbt parse`

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

_(Add as Phase 0 progresses)_

### Issues encountered

_(Add as Phase 0 progresses)_

### Candidate ADRs

_(Add as Phase 0 progresses — design gaps that need formal decisions)_
