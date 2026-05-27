# Spark Retail Pack

> **A productized data warehouse accelerator for direct-to-consumer retail and e-commerce.**
> Built on Snowflake + dbt Core + Power BI. Open-core distribution.

[![License: MIT (core)](https://img.shields.io/badge/license-MIT%20(core)-blue)](./02_dbt_core/LICENSE)
[![dbt: 1.8+](https://img.shields.io/badge/dbt-1.8%2B-orange)](https://docs.getdbt.com)
[![Snowflake](https://img.shields.io/badge/warehouse-Snowflake-29B5E8)](https://snowflake.com)
[![Build: passing](https://img.shields.io/badge/build-passing-brightgreen)]()

---

## What this is

The Spark Retail Pack lets a mid-market D2C retailer ($5M–$200M GMV) stand up a fully modeled, governed analytics warehouse in **4–6 weeks** instead of 6+ months.

It ships as two tiers:

- **Open-source core** (MIT) — the complete canonical data model, all 5 source connectors, 14 KPIs, governance machinery, and a deterministic demo data generator. Free, forever.
- **Pro tier** (commercial license) — the semantic layer encoding, 3 Power BI dashboard packs, 11 advanced KPIs, 6 proprietary macros, and AI-ready metadata.

If you want to evaluate the OSS core locally, you can be running demo data through `dbt build` in under 15 minutes. No Snowflake account required for the first steps.

---

## Quick start

### 1. Clone and install

```bash
git clone https://github.com/Spark-Analytics-Demos/spark-retail-pack.git
cd spark-retail-pack
pip install -r 05_demo_data/requirements.txt
```

### 2. Generate demo data (no Snowflake needed)

```bash
cd 05_demo_data
python generators/main.py --tier small
# Produces ~1.2M rows of Northwind Co. synthetic retail data in ~2 minutes
# Output: 05_demo_data/datasets/small/
```

### 3. Validate the dbt project

```bash
cd ../02_dbt_core
pip install dbt-snowflake
dbt deps
dbt parse
# Should complete with 0 errors (warnings on empty sources are expected)
```

### 4. Connect to Snowflake and build

Copy the profiles template and fill in your credentials:

```bash
cp profiles.yml.template profiles.yml
# Edit profiles.yml — fill in account, user, password, warehouse, database, schema
```

Load the demo data to your Snowflake bronze layer:

```bash
cd ../05_demo_data/loaders
snowsql -f load_to_snowflake_bronze.sql
```

Run the full build:

```bash
cd ../../02_dbt_core
dbt build
# Runs all staging → intermediate → core → mart models + tests
```

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Python | 3.11+ | For the demo data generator |
| dbt Core | 1.8+ | `pip install dbt-snowflake` installs Core + Snowflake adapter |
| Snowflake | Any edition | Free trial works; XSmall warehouse is sufficient |
| SnowSQL | 1.2+ | For loading demo data; optional if using Fivetran/Airbyte |
| git | Any | — |

A Snowflake account is only required for Steps 4 onwards. Steps 1–3 run entirely locally and are useful for exploring the project before provisioning infrastructure.

---

## What's in the OSS core

Everything needed to stand up the canonical warehouse layer:

| Layer | Contents |
|---|---|
| **Staging** | 5 source connectors: Shopify, Stripe, Google Analytics 4, Meta Ads, Klaviyo |
| **Intermediate** | Identity resolution (3-tier: email, phone, fuzzy name+address), FX normalisation, channel enrichment |
| **Core dimensions** | `dim_customer`, `dim_product`, `dim_date`, `dim_channel`, `dim_geography`, `dim_campaign`, `dim_variant`, `dim_location`, `dim_currency` |
| **Core facts** | `fact_orders`, `fact_order_lines`, `fact_refunds`, `fact_web_sessions`, `fact_email_engagement`, `fact_marketing_spend`, `fact_inventory_snapshot`, `fact_inventory_movements`, `fact_customer_state_daily` |
| **Marts** | `mart_sales`, `mart_customer`, `mart_inventory` — 14 production-grade KPIs |
| **Governance** | PII masking by default, GDPR/CCPA erasure macro, 8-column audit footer on every table, lineage views, 7-role Snowflake access hierarchy |
| **Macros** | 9 OSS macros: `add_audit_columns`, `generate_dim_sk`, `pii_mask`, `customer_erasure`, `apply_source_mapping`, `incremental_lookback`, `daily_fx_rate`, `quarantine_failed_rows`, `lineage_edges` |
| **Demo data** | Northwind Co. synthetic retailer — 5 embedded story arcs, 3 volume tiers (small/medium/large), deterministic generation |
| **CI/CD** | GitHub Actions workflows for PR validation and deploy; SQLFluff + YAML lint; dbt docs publishing |

The 14 OSS KPIs cover the fundamentals: GMV, Net Revenue, Order Count, AOV, Revenue Growth %, Tax Collected, Active Customers (30d/90d), New Customers, Repeat Customer Count, Repeat Purchase Rate, Total Inventory Value, Days of Supply, and Stockout Rate.

---

## What the Pro tier adds

| Component | Description |
|---|---|
| **3 Power BI dashboards** | Executive Summary, Customer 360, Inventory Health — 5 pages each, pre-built and themed |
| **Semantic layer** | MetricFlow YAML encoding all 25 KPIs — single source of truth for metrics across Power BI, AI assistant, and ad-hoc queries |
| **11 advanced KPIs** | Customer LTV, CAC by channel, ROAS, Refund Rate, Return Rate, Revenue by Channel, Email Engagement Rate, Inventory Turnover, Sell-Through Rate, Slow-Moving SKU Count, Average Time Between Orders |
| **6 proprietary macros** | RFM segmentation, cohort retention, first-touch and last-touch attribution, churn risk scoring, inventory velocity flags |
| **AI-ready metadata** | Metric synonyms, example queries, domain knowledge facts for natural-language querying |
| **Implementation playbook** | 30-day engagement guide for the Spark Analytics deployment team |

See [`01_design_docs/11_open_source_vs_pro_split.md`](./01_design_docs/11_open_source_vs_pro_split.md) for the full component-by-component split and the commercial rationale.

---

## Repository layout

```
spark-retail-pack/
├── 01_design_docs/        ← Complete v1 design specification (13 sections + 4 ADRs)
├── 02_dbt_core/           ← Open-source dbt project (MIT-licensed)
│   ├── models/
│   │   ├── staging/       ← stg_<source>__<table>.sql — one per source table
│   │   ├── intermediate/  ← int_*.sql — identity resolution, FX, enrichment
│   │   ├── core/          ← dim_*.sql and fact_*.sql — canonical model
│   │   └── marts/         ← mart_<module>/ — KPI-ready aggregations
│   ├── macros/            ← 9 OSS macros
│   ├── seeds/             ← Source mappings, category mappings, config
│   ├── tests/             ← Business-rule singular tests
│   └── snapshots/         ← SCD2 snapshots for slowly-changing dimensions
├── 03_dbt_pro/            ← Proprietary dbt project (commercial license)
├── 04_dashboards/         ← Power BI .pbix files (proprietary)
├── 05_demo_data/          ← Northwind Co. synthetic data generator + QA
├── 06_governance/         ← Governance YAML artifacts (ownership, classification, PII)
└── 07_decisions/          ← Architecture Decision Records (ADR-001 through ADR-004)
```

---

## The demo data

The pack ships with **Northwind Co.** — a fictional D2C apparel retailer with $24M GMV, ~120K orders/year, ~85K customers, and ~2,400 SKUs across 4 markets.

Five business events are embedded in the 12-month dataset, each visible in the dashboards without configuration:

| Story | Period | What you see |
|---|---|---|
| Black Friday spike | Nov 28–Dec 1 | 8.2× daily GMV, 1,400 new customers in a day, 78 SKUs stockout |
| Inventory crisis | Apr 8–25 | Top SKU (`HJ-001-MED-BLU`) at zero stock for 17 days, $180K lost revenue |
| Pricing churn | Jun–Aug | Sweater +12% → Repeat Purchase Rate dips from 28% to 22% |
| Viral moment | Sep 14–28 | Influencer post → 600 new customers/day, CAC drops to $31 |
| Failed product line | Mar–May | Resort Wear 18 SKUs, 22% sell-through vs. 60% expected |

Three volume tiers ship from the same generator:

| Tier | Orders | Use case | Generate time |
|---|---|---|---|
| Small (`--tier small`) | 5,000 | Local dev, unit tests | ~2 min |
| Medium (`--tier medium`) | 120,000 | Default demo, CI | ~8 min |
| Large (`--tier large`) | 600,000 | Load testing, enterprise demo | ~25 min |

```bash
# Regenerate any tier
cd 05_demo_data
python generators/main.py --tier medium --seed 42
```

Generated datasets are not committed to the repo (they're regeneratable). The generator is deterministic: same `--seed` produces byte-identical output.

---

## The canonical data model

The full model specification is in [`01_design_docs/04_canonical_data_model_*.md`](./01_design_docs/). Key design decisions:

- **All monetary values in USD** (reporting currency), with FX conversion in the intermediate layer
- **Surrogate keys** via SHA-256 hash of natural key components, generated by the `generate_surrogate_key` macro
- **8-column audit footer** on every core and mart table: `_loaded_at`, `_updated_at`, `_source_system`, `_source_id`, `_is_deleted`, `_dbt_run_id`, `_dbt_model`, `_row_hash`
- **SCD2** for `dim_customer` and `dim_product` — full history preserved via dbt snapshots
- **Incremental loads** with a configurable lookback window on all facts — safe for late-arriving data
- **PII masked by default** in staging and production; unmasked in dev environments. Erasure via `dbt run-operation customer_erasure`

---

## Snowflake setup

The pack expects the following Snowflake objects. Scripts to provision them are in `setup/snowflake/`:

```
Databases:    RAW_RETAIL, ANALYTICS_RETAIL_DEV, ANALYTICS_RETAIL_STAGING, ANALYTICS_RETAIL
Warehouses:   WH_LOAD, WH_TRANSFORM, WH_BI, WH_ADHOC
Roles:        RETAIL_LOADER, RETAIL_TRANSFORMER, RETAIL_BI_READER, RETAIL_ANALYST,
              RETAIL_PII_VIEWER, RETAIL_FINANCE_VIEWER, RETAIL_ADMIN
```

If you're starting from scratch, run the setup scripts in order:
```
01_databases_and_schemas.sql → 02_warehouses.sql → 03_roles.sql → 04_grants.sql → 05_service_accounts.sql → 06_resource_monitors.sql
```

Or use the automated runner (reads credentials from environment variables, never from code):
```bash
cd setup/snowflake
python run_provisioning.py
```

Each script is idempotent. See [`01_design_docs/02_architecture.md`](./01_design_docs/02_architecture.md) §2.5 for the full role hierarchy and permission model.

---

## CI/CD

GitHub Actions workflows ship in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `dbt-ci.yml` | Pull request | `dbt deps` → `dbt parse` → `dbt build --select state:modified+` → SQLFluff lint |
| `dbt-deploy.yml` | Merge to `main` | Full `dbt build` against staging environment |
| `dbt-docs.yml` | Push to `main` | `dbt docs generate` → publish to GitHub Pages |

Required GitHub Actions secrets:

| Secret | Value |
|---|---|
| `SNOWFLAKE_ACCOUNT` | Your Snowflake account identifier |
| `SNOWFLAKE_CI_USER` | Service account username (e.g., `SVC_DBT`) |
| `SNOWFLAKE_CI_PASSWORD` | Service account password |
| `SNOWFLAKE_USER` | Deploy service account username |
| `SNOWFLAKE_PASSWORD` | Deploy service account password |
| `PII_HASH_SALT` | Random 32+ character string — keep consistent across environments |

---

## Documentation

| Topic | Where |
|---|---|
| What this is and who it's for | [`01_executive_overview.md`](./01_design_docs/01_executive_overview.md) |
| Architecture and Snowflake setup | [`02_architecture.md`](./01_design_docs/02_architecture.md) |
| Module breakdown (Sales, Customer 360, Inventory) | [`03_module_breakdown.md`](./01_design_docs/03_module_breakdown.md) |
| Canonical data model — dimensions | [`04_canonical_data_model_part1_dimensions.md`](./01_design_docs/04_canonical_data_model_part1_dimensions.md) |
| Canonical data model — facts | [`04_canonical_data_model_part2_facts.md`](./01_design_docs/04_canonical_data_model_part2_facts.md) |
| Implementation standards | [`04_canonical_data_model_part3_implementation_standards.md`](./01_design_docs/04_canonical_data_model_part3_implementation_standards.md) |
| KPI catalog (all 25) | [`05_kpi_catalog.md`](./01_design_docs/05_kpi_catalog.md) |
| Connector specifications | [`06_connector_specs.md`](./01_design_docs/06_connector_specs.md) |
| Semantic layer | [`07_semantic_layer.md`](./01_design_docs/07_semantic_layer.md) |
| Governance baseline | [`08_governance_baseline.md`](./01_design_docs/08_governance_baseline.md) |
| Demo data design (Northwind Co.) | [`09_demo_data_design.md`](./01_design_docs/09_demo_data_design.md) |
| OSS vs. Pro split | [`11_open_source_vs_pro_split.md`](./01_design_docs/11_open_source_vs_pro_split.md) |
| Build roadmap | [`12_build_roadmap.md`](./01_design_docs/12_build_roadmap.md) |
| Architecture decisions (ADRs) | [`07_decisions/`](./07_decisions/) |

The dbt docs site (auto-generated on every push to `main`) is published at: **https://spark-analytics-demos.github.io/spark-retail-pack/**

---

## Contributing

Contributions to the open-source core (`02_dbt_core/`) are welcome. Before opening a PR:

1. Read [`CONTRIBUTING.md`](./CONTRIBUTING.md) — covers code conventions, test requirements, and the CLA process
2. Check the [open issues](https://github.com/Spark-Analytics-Demos/spark-retail-pack/issues) to avoid duplicate work
3. For anything larger than a bug fix, open an issue first to discuss approach

The contribution boundary is enforced: `02_dbt_core/` is open for community PRs; `03_dbt_pro/` is not.

---

## License

| Directory | License |
|---|---|
| `02_dbt_core/` | [MIT](./02_dbt_core/LICENSE) |
| `05_demo_data/` (generator + scripts) | [MIT](./02_dbt_core/LICENSE) |
| `06_governance/` | [MIT](./02_dbt_core/LICENSE) |
| `01_design_docs/` | All rights reserved — Spark Analytics |
| `03_dbt_pro/`, `04_dashboards/` | Commercial license — contact Spark Analytics |

---

## Maintained by

**Spark Analytics** — [sparkanalytics.co.ke](https://sparkanalytics.co.ke)

Commercial inquiries: [info@sparkanalytics.co.ke](mailto:info@sparkanalytics.co.ke)

Technical questions: [open a GitHub issue](https://github.com/Spark-Analytics-Demos/spark-retail-pack/issues)
