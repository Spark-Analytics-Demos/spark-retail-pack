# spark_retail_pack — Open Source dbt Project

> **Status:** Scaffolded (Phase 0). Ready for Phase 1 model development.
> **License:** MIT (when published)

This is the open-source core of the Spark Retail Pack. It contains:

- The entire canonical data model (9 dimensions, 9 facts)
- Staging models for all 5 source connectors
- 14 of 25 KPIs (the OSS tier)
- 9 OSS macros
- Governance machinery (audit columns, PII handling, erasure)

See `../01_design_docs/11_open_source_vs_pro_split.md` for the full OSS/Pro split.

---

## Folder structure

```
02_dbt_core/
├── dbt_project.yml         ← project configuration
├── packages.yml            ← pinned dependencies
├── profiles.yml.template   ← profile template (real profiles.yml is gitignored)
├── README.md               ← this file
├── models/
│   ├── staging/            ← stg_<source>__<table>.sql
│   │   ├── shopify/
│   │   ├── stripe/
│   │   ├── ga4/
│   │   ├── meta_ads/
│   │   └── klaviyo/
│   ├── intermediate/       ← int_*.sql (identity resolution, enrichment)
│   ├── core/
│   │   ├── dimensions/     ← dim_*.sql
│   │   └── facts/          ← fact_*.sql
│   └── marts/
│       ├── sales/
│       ├── customer/
│       └── inventory/
├── seeds/
│   └── source_mappings/    ← YAML mapping configs per Section 6.2
├── macros/
│   ├── audit/              ← add_audit_columns
│   ├── keys/               ← generate_dim_sk
│   ├── source_mapping/     ← apply_source_mapping
│   ├── pii/                ← pii_mask
│   ├── quality/            ← quarantine_failed_rows
│   ├── privacy/            ← customer_erasure
│   ├── currency/           ← daily_fx_rate
│   ├── incremental/        ← incremental_lookback
│   └── metadata/           ← lineage_edges
├── tests/
├── snapshots/
├── analyses/
└── docs/
```

---

## Getting started

### Prerequisites

1. Python 3.11+ with `pip`
2. dbt 1.7+ (`pip install dbt-core dbt-snowflake`)
3. Snowflake account with the 7 roles set up per Section 2.5
4. `profiles.yml` configured (copy from `profiles.yml.template`)

### First run

```bash
# From the 02_dbt_core/ directory
dbt deps              # install packages
dbt parse             # verify project is well-formed
dbt debug             # verify connection to Snowflake
```

When the first models exist, run:

```bash
dbt build --select state:modified+   # build only changed models and dependencies
dbt test                              # run all tests
dbt docs generate && dbt docs serve   # browse the docs site
```

---

## Conventions

See `../CLAUDE.md` for the full convention reference. Key points:

- **Naming:** `stg_<source>__<table>`, `dim_<entity>`, `fact_<event>`, `int_<purpose>`
- **Audit columns:** Every core and mart model uses the `add_audit_columns` macro
- **Tests:** `not_null`, `unique`, `relationships` minimum per Section 4 Part 3 §4.37
- **PII handling:** Every PII column uses the `pii_mask` macro per Section 8.5

---

## Design document references

| Folder | Defines |
|---|---|
| `models/staging/` | Section 6 (Connector Specs) |
| `models/intermediate/` | Section 4 Part 1 §4.3 (identity resolution) |
| `models/core/dimensions/` | Section 4 Part 1 (9 dimensions) |
| `models/core/facts/` | Section 4 Part 2 (9 facts) |
| `models/marts/` | Section 3 (3 modules) and Section 5 (14 OSS KPIs) |
| `macros/` | Section 4 Part 3 §4.47 (9 OSS macros) |
| `seeds/source_mappings/` | Section 6.2 (mapping config pattern) |
| `snapshots/` | Section 4 Part 3 §4.34 (SCD2 pattern) |

---

## What does NOT belong here

- Power BI dashboard files → `../04_dashboards/`
- Semantic layer YAML → `../03_dbt_pro/models/semantic/`
- Pro KPIs (LTV, CAC, attribution, etc.) → `../03_dbt_pro/`
- Demo data generator → `../05_demo_data/`
- Governance YAML artifacts → `../06_governance/`

Adding Pro features here erodes the open-core boundary. See CLAUDE.md §"What you should refuse."
