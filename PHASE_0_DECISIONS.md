# Phase 0 — Kickoff Decisions

> **Status:** Locked  
> **Date:** 2026-05-26  
> **Authority:** Per Section 13.3 and PHASE_0_CHECKLIST §0.1, these six decisions must be locked before infrastructure provisioning begins. Any change requires an ADR or explicit revision to this file.

---

## Decision 1 — dbt execution path

**Decision:** dbt Core  
**Reference:** ADR-004

dbt Core runs locally and in CI via the open-source CLI. dbt Cloud is not used in v1. The Semantic Layer is accessed via Path 2 (materialized views in the `SEMANTIC` schema) until/unless dbt Cloud is added later.

If the team later needs Path 1 (dbt Cloud GraphQL API for the Semantic Layer), adopt it as a separate ADR rather than silently layering it in.

---

## Decision 2 — Reporting currency

**Decision:** USD  
**Reference:** Section 4 Part 1 §4.11  
**dbt var:** `reporting_currency: 'USD'`

All monetary values in core and mart tables are converted to USD at the transaction-date FX rate. The FX seed table (`seeds/fx_rates.csv`) uses USD as the base. Multi-currency display variants are deferred to v2.

---

## Decision 3 — Reporting timezone

**Decision:** Africa/Nairobi (EAT, UTC+3)  
**Reference:** Section 4 Part 1 §4.7  
**dbt var:** `reporting_timezone: 'Africa/Nairobi'`

East African Time, UTC+3, no daylight-saving transitions. All date/time dimensions (`dim_date`, `dim_time`) and KPI windows use this timezone. Raw timestamps from source connectors are stored in UTC and converted at the staging layer.

---

## Decision 4 — Snowflake region

**Decision:** AWS us-west-2 (US West — Oregon)  
**Reference:** Section 2.5  
**Account identifier format:** `<account_locator>.us-west-2.aws`

All four databases (`RAW_RETAIL`, `ANALYTICS_RETAIL_DEV`, `ANALYTICS_RETAIL_STAGING`, `ANALYTICS_RETAIL`) are created in this region. If a client requires EU data residency, a separate account in `eu-west-1` must be provisioned — do not share accounts across regions.

---

## Decision 5 — PII handling level

**Decision:** Full SHA-256 hashing in staging and prod; masking disabled in dev (synthetic data only)  
**Reference:** Section 8.5  
**dbt vars:** `pii_masking_enabled: true`, `pii_hashing_method: 'sha256'`

The `pii_mask` macro applies SHA-256 + salt (from `PII_HASH_SALT` env var) to all columns tagged `pii_present: true` in schema.yml. The salt is managed via the secrets manager — never hardcoded. In dev, `pii_masking_enabled` is set to `false` because only synthetic Northwind Co. data is used; this must never be overridden when real client data is present.

---

## Decision 6 — Retention horizons

**Decision:** Section 8.9 defaults, unmodified  
**Reference:** Section 8.9

Default retention horizons apply as specified. No client-specific modifications for v1. The governance YAML artifact (`06_governance/retention.yml`) will encode these defaults when built in Phase 4.

---

## Change log

| Date | Decision | Change | Author |
|---|---|---|---|
| 2026-05-26 | All six | Initial lock | DenisKiberaWanjohi |
