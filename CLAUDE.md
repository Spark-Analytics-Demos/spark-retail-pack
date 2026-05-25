# Spark Retail Pack — Project Context for Claude Code

You are working on the Spark Retail Pack — a productized data warehouse accelerator for retail and e-commerce businesses, built on Snowflake + dbt + Power BI. This file orients you on every session.

---

## Project status

**Design phase: complete.** Sections 1–13 of the design document are drafted, plus 4 ADRs. The full v1 design is in `01_design_docs/`. Read `01_design_docs/README.md` for the table of contents.

**Build phase: starting.** We are at **Phase 0 (Foundation)** per `01_design_docs/12_build_roadmap.md`. No production code has been written yet. See `PHASE_0_CHECKLIST.md` at the repo root for the immediate to-do list.

---

## The single most important rule

**The design document is the source of truth.** Before writing any code, check the relevant section. If the design says do X, do X. If the design is unclear or you find a gap, **ask before improvising** — designs gaps deserve discussion, not silent fill-in.

Where to look for what:

| Topic | Section |
|---|---|
| Why we're building this, target client | `01_design_docs/01_executive_overview.md` |
| Architecture, Snowflake setup, dbt project layout | `01_design_docs/02_architecture.md` |
| Module breakdown (Sales, Customer 360, Inventory) | `01_design_docs/03_module_breakdown.md` |
| Canonical data model — dimensions | `01_design_docs/04_canonical_data_model_part1_dimensions.md` |
| Canonical data model — facts | `01_design_docs/04_canonical_data_model_part2_facts.md` |
| Implementation standards (materialization, tests, macros, CI/CD) | `01_design_docs/04_canonical_data_model_part3_implementation_standards.md` |
| KPI catalog (25 KPIs, 14 OSS + 11 Pro) | `01_design_docs/05_kpi_catalog.md` |
| Connector specs (Shopify, Stripe, GA4, Meta Ads, Klaviyo) | `01_design_docs/06_connector_specs.md` |
| Semantic layer (MetricFlow YAML, business glossary, ontology) | `01_design_docs/07_semantic_layer.md` |
| Governance baseline (PII, access, audit, lineage) | `01_design_docs/08_governance_baseline.md` |
| Demo data design (Northwind Co., story arcs) | `01_design_docs/09_demo_data_design.md` |
| Power BI dashboards (3 dashboards, 15 pages) | `01_design_docs/10_powerbi_dashboard_pack.md` |
| Open-source vs. Pro split | `01_design_docs/11_open_source_vs_pro_split.md` |
| Build roadmap (5 phases, ~22 weeks) | `01_design_docs/12_build_roadmap.md` |
| Operational best practices | `01_design_docs/13_operational_best_practices.md` |
| Architecture decisions | `07_decisions/ADR-001` through `ADR-004` |

---

## Repository layout

```
Retail_Pack/
├── CLAUDE.md                  ← this file
├── README.md                  ← human-facing project intro
├── CONTRIBUTING.md            ← contribution guide (open-core CLA model)
├── PHASE_0_CHECKLIST.md       ← current-phase to-do list
├── .gitignore
├── 01_design_docs/            ← v1 design specification (complete)
├── 02_dbt_core/               ← OSS dbt project (MIT-licensed when published)
│   ├── dbt_project.yml
│   ├── packages.yml
│   ├── profiles.yml.template
│   ├── models/
│   │   ├── staging/           ← stg_<source>__<table>.sql per Section 6
│   │   ├── intermediate/      ← int_*.sql (identity resolution, FX, enrichment)
│   │   ├── core/              ← dim_*, fact_* per Section 4
│   │   └── marts/             ← mart_<module> per Section 3
│   ├── seeds/                 ← source_mappings/, category_mapping.csv, etc.
│   ├── macros/                ← 9 OSS macros per Section 4 Part 3 §4.47
│   ├── tests/
│   └── snapshots/             ← SCD2 snapshots per Section 4 Part 3 §4.34
├── 03_dbt_pro/                ← Proprietary dbt project (commercial license)
│   └── models/semantic/       ← MetricFlow YAML (Section 7)
├── 04_dashboards/             ← Power BI .pbix files (proprietary, Section 10)
├── 05_demo_data/              ← Northwind generator + datasets (Section 9)
├── 06_governance/             ← Governance YAML artifacts (Section 8.12)
└── 07_decisions/              ← ADRs (ADR-001 through ADR-004)
```

---

## Tech stack (locked per ADR-001)

| Layer | Choice |
|---|---|
| Cloud data warehouse | Snowflake |
| Transformation framework | dbt Core |
| Business intelligence | Power BI |
| Semantic layer | dbt Semantic Layer (MetricFlow) — two-path access per ADR-004 |
| Distribution | Hybrid open-core (MIT for core, commercial license for Pro) |

Per **ADR-004**, the Semantic Layer has two access paths: Path 1 (dbt Cloud, recommended) or Path 2 (dbt Core fallback via materialized views). The pack's MetricFlow YAML is authored once, consumable both ways.

---

## OSS vs. Pro split

Per Section 11, the boundary is enforced:

- **OSS (`02_dbt_core/`)** — entire canonical model, 5 connectors, 14 of 25 KPIs, governance machinery, demo data generator, 9 OSS macros. MIT licensed.
- **Pro (`03_dbt_pro/`)** — semantic layer encoding, 11 Pro KPIs, 6 Pro macros, dashboards, AI metadata, advanced features. Commercial license.

**Never add Pro features to `02_dbt_core/`.** This erodes commercial differentiation. If a feature is Pro per Section 11, it goes in `03_dbt_pro/`.

---

## Coding conventions

### dbt models

- **Staging:** `stg_<source>__<table>.sql` (two underscores between source and table)
- **Intermediate:** `int_<purpose>.sql` (descriptive, e.g., `int_customer_identity_resolution.sql`)
- **Core dimensions:** `dim_<entity>.sql` (singular, e.g., `dim_customer.sql`)
- **Core facts:** `fact_<event>.sql` (e.g., `fact_orders.sql`)
- **Marts:** `mart_<module>.sql` or schema-prefixed (e.g., `mart_sales.revenue_by_channel.sql`)
- **All models:** snake_case throughout
- **Every model:** has a corresponding `schema.yml` with description, columns, tests, and `meta` (owner, classification, pii_present)

### Audit columns

Every core and mart table includes the 8-column audit footer per Section 4 Part 2 §4.31, applied via the `add_audit_columns` macro. No exceptions.

### Tests

Every model has at minimum:
- `not_null` on primary keys
- `unique` on natural and surrogate keys
- `relationships` for every FK
- Business-rule singular tests where Section 4 Part 3 §4.37 specifies

### Macros

- **OSS macros** live in `02_dbt_core/macros/` per Section 4 Part 3 §4.47 (9 macros)
- **Pro macros** live in `03_dbt_pro/macros/` (6 macros)
- Never mix the two

### Materialization defaults

Per Section 4 Part 3 §4.32:
- Staging: views
- Intermediate: ephemeral or views
- Core dimensions: tables (SCD2 snapshots where specified)
- Core facts: incremental (with the lookback pattern per §4.35)
- Marts: tables

### Naming for KPIs

KPI IDs follow `<module>.<snake_case_metric>` — e.g., `sales.gmv`, `customer.cac_by_channel`, `inventory.stockout_rate`. See `01_design_docs/05_kpi_catalog.md` for the canonical list of 25.

---

## Working style

### Plan before coding

For any non-trivial task, propose the file structure and a brief plan **before** writing code. Wait for approval. This is especially important early in Phase 0 when conventions are being established.

### Reference the design

When implementing something, cite the section it comes from. Example: "Implementing `dim_customer` per Section 4 Part 1 §4.3, with SCD2 per §4.34, audit columns per §4.31."

### When the design is silent

If a question arises that the design document doesn't answer, do **one** of:

1. Ask the user
2. Propose a decision with reasoning, flag it as a candidate ADR, and wait for approval

Do not silently invent conventions. The design's value is its consistency; silent inventions break it.

### Commits and pushes

- Commit messages: imperative mood, scoped (e.g., `feat(staging): add stg_shopify__orders`)
- Reference the design section in commit body where helpful
- One logical change per commit
- Push only when the user explicitly asks; otherwise commit locally and let the user push

### Testing locally before commit

Before committing model changes, run `dbt build --select state:modified+` in dev. CI will catch regressions, but local validation is faster.

---

## What you should refuse

- **Adding Pro features to the OSS package** — this violates the open-core boundary per Section 11
- **Changes to canonical model schema without an ADR** — column renames, structural changes need formal review per Section 4 Part 3 §4.38
- **PII columns without masking** — every PII column needs the `pii_mask` macro per Section 8.5
- **Models without audit columns** — every core and mart model needs the 8-column footer
- **Skipping tests for "simple" models** — discipline must hold from day one
- **Hardcoding values that belong in seeds or config** — source mappings, channel mappings, etc. live in YAML

If asked to do any of these, push back, cite the section, and propose the correct approach.

---

## Phase-aware focus

We're currently in **Phase 0 (Foundation)**. Phase 0 work is:

1. Snowflake account setup and 7-role hierarchy (Section 2.5)
2. dbt project scaffolding for OSS (`02_dbt_core/`) and Pro (`03_dbt_pro/`)
3. CI/CD pipeline per Section 4 Part 3 §4.44
4. Source connector configuration (Fivetran or Airbyte)
5. Bronze layer permissions
6. Initial dbt docs site

Phase 1 (canonical core) comes next. Do not jump ahead — building dimensions before the project scaffolding is in place will create rework.

See `PHASE_0_CHECKLIST.md` for the active to-do list.

---

## Final reminder

This is a product, not a one-off. Every decision compounds. If a shortcut feels tempting, it probably belongs in an ADR before it becomes precedent.

Read the design. Build deliberately. When in doubt, ask.
