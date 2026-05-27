# Spark Retail Pack — OSS Core

> **A productized data warehouse accelerator for direct-to-consumer retail and e-commerce.**
> Built on Snowflake + dbt Core + Power BI. Open-core distribution.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](./02_dbt_core/LICENSE)
[![dbt: 1.8+](https://img.shields.io/badge/dbt-1.8%2B-orange)](https://docs.getdbt.com)
[![Snowflake](https://img.shields.io/badge/warehouse-Snowflake-29B5E8)](https://snowflake.com)

---

## What this is

The Spark Retail Pack lets a mid-market D2C retailer ($5M–$200M GMV) stand up a fully modeled, governed analytics warehouse in **4–6 weeks** instead of 6+ months.

This repository contains the **open-source model layer** — the canonical staging, core dimension, core fact, and mart models for Shopify, Stripe, GA4, Meta Ads, and Klaviyo, plus the Northwind Co. demo data generator. The model code is MIT licensed and free to inspect, fork, and adapt.

The **Pro tier** includes everything needed to deploy and run the project: the macro library, intermediate transformation layer, governance machinery, Snowflake provisioning scripts, CI/CD workflows, semantic layer, Power BI dashboards, and the full design specification. Contact [info@sparkanalytics.co.ke](mailto:info@sparkanalytics.co.ke) for access.

---

## What's in the OSS model layer

| Layer | Contents |
|---|---|
| **Staging** | 5 source connectors: Shopify, Stripe, Google Analytics 4, Meta Ads, Klaviyo — 26 staging models |
| **Core dimensions** | `dim_customer`, `dim_product`, `dim_date`, `dim_channel`, `dim_geography`, `dim_campaign`, `dim_variant`, `dim_location`, `dim_currency` |
| **Core facts** | `fact_orders`, `fact_order_lines`, `fact_refunds`, `fact_web_sessions`, `fact_email_engagement`, `fact_marketing_spend`, `fact_inventory_snapshot`, `fact_inventory_movements`, `fact_customer_state_daily` |
| **Marts** | `mart_sales`, `mart_customer`, `mart_inventory` — 14 production-grade KPIs |
| **Seeds** | Channel mapping, FX rates, geography, holidays, product category mapping, source connector overrides |
| **Tests** | 4 singular business-rule tests (monetary balance, movement sign convention, order/line integrity, refund integrity) |
| **Snapshots** | SCD2 snapshots for `dim_customer`, `dim_product`, `dim_marketing_campaign` |
| **Demo data** | Northwind Co. synthetic retailer — 5 embedded story arcs, 3 volume tiers, deterministic generation |

The 14 OSS KPIs: GMV, Net Revenue, Order Count, AOV, Revenue Growth %, Tax Collected, Active Customers (30d/90d), New Customers, Repeat Customer Count, Repeat Purchase Rate, Total Inventory Value, Days of Supply, Stockout Rate.

---

## What the Pro tier adds

| Component | Description |
|---|---|
| **Macro library** | 9 OSS macros (`add_audit_columns`, `generate_dim_sk`, `pii_mask`, `customer_erasure`, `apply_source_mapping`, `incremental_lookback`, `daily_fx_rate`, `quarantine_failed_rows`, `lineage_edges`) required to build the models in this repo |
| **Intermediate layer** | Identity resolution (3-tier: email, phone, fuzzy name+address), FX normalisation, GA4 session aggregation, order enrichment |
| **Governance machinery** | PII masking, GDPR/CCPA erasure workflow, audit footer on every table, lineage views |
| **6 Pro macros** | RFM segmentation, cohort retention, first-touch and last-touch attribution, churn risk scoring, inventory velocity flags |
| **Semantic layer** | MetricFlow YAML encoding all 25 KPIs — single source of truth for Power BI, AI assistant, and ad-hoc queries |
| **11 advanced KPIs** | Customer LTV, CAC by channel, ROAS, Refund Rate, Return Rate, Revenue by Channel, Email Engagement Rate, Inventory Turnover, Sell-Through Rate, Slow-Moving SKU Count, Average Time Between Orders |
| **3 Power BI dashboards** | Executive Summary, Customer 360, Inventory Health — 5 pages each, pre-built and themed |
| **AI-ready metadata** | Metric synonyms, example queries, domain knowledge facts |
| **Snowflake setup scripts** | Idempotent SQL to provision databases, warehouses, 7-role access hierarchy, and service accounts |
| **CI/CD workflows** | GitHub Actions for PR validation, staging deploys, and automated dbt docs publishing |
| **Full design specification** | 13-section product blueprint, KPI catalog, connector specs, governance baseline, build roadmap, ADRs |
| **Implementation playbook** | 30-day engagement guide for the Spark Analytics deployment team |

Contact [info@sparkanalytics.co.ke](mailto:info@sparkanalytics.co.ke) for Pro access.

---

## Exploring the models

Clone the repo and browse the model code:

```bash
git clone https://github.com/Spark-Analytics-Demos/spark-retail-pack.git
cd spark-retail-pack
```

The staging models (`02_dbt_core/models/staging/`) show the exact transformations applied to each source connector. The core and mart models (`02_dbt_core/models/core/`, `02_dbt_core/models/marts/`) show the canonical dimensional schema and KPI definitions.

To generate and explore the Northwind Co. demo dataset locally (no Snowflake needed):

```bash
pip install -r 05_demo_data/requirements.txt
cd 05_demo_data
python generators/main.py --tier small
# Output: 05_demo_data/datasets/small/
```

To build and run the full project against Snowflake, the Pro tier is required (macros and intermediate layer). Contact [info@sparkanalytics.co.ke](mailto:info@sparkanalytics.co.ke).

---

## Repository layout

```
spark-retail-pack/
├── 02_dbt_core/           ← Open-source model layer (MIT-licensed)
│   ├── models/
│   │   ├── staging/       ← stg_<source>__<table>.sql — one per source table
│   │   ├── core/          ← dim_*.sql and fact_*.sql — canonical model
│   │   └── marts/         ← mart_<module>/ — KPI-ready aggregations
│   ├── seeds/             ← Source mappings, category mappings, reference data
│   ├── tests/             ← Business-rule singular tests
│   └── snapshots/         ← SCD2 snapshots for slowly-changing dimensions
├── 04_dashboards/         ← Power BI .pbix files (Pro — delivered separately)
└── 05_demo_data/          ← Northwind Co. synthetic data generator + QA
```

---

## The demo data

The pack ships with **Northwind Co.** — a fictional D2C apparel retailer with $24M GMV, ~120K orders/year, ~85K customers, and ~2,400 SKUs across 4 markets.

Five business events are embedded in the 12-month dataset:

| Story | Period | What you see |
|---|---|---|
| Black Friday spike | Nov 28–Dec 1 | 8.2× daily GMV, 1,400 new customers in a day, 78 SKUs stockout |
| Inventory crisis | Apr 8–25 | Top SKU (`HJ-001-MED-BLU`) at zero stock for 17 days, $180K lost revenue |
| Pricing churn | Jun–Aug | Sweater +12% → Repeat Purchase Rate dips from 28% to 22% |
| Viral moment | Sep 14–28 | Influencer post → 600 new customers/day, CAC drops to $31 |
| Failed product line | Mar–May | Resort Wear 18 SKUs, 22% sell-through vs. 60% expected |

| Tier | Orders | Use case | Generate time |
|---|---|---|---|
| Small (`--tier small`) | 5,000 | Local dev, unit tests | ~2 min |
| Medium (`--tier medium`) | 120,000 | Default demo, CI | ~8 min |
| Large (`--tier large`) | 600,000 | Load testing, enterprise demo | ~25 min |

```bash
cd 05_demo_data
python generators/main.py --tier medium --seed 42
```

Generated datasets are not committed to the repo. The generator is deterministic: same `--seed` produces byte-identical output.

---

## Contributing

Contributions to the open-source model layer (`02_dbt_core/`) are welcome. Before opening a PR:

1. Read [`CONTRIBUTING.md`](./CONTRIBUTING.md) — covers code conventions, test requirements, and the CLA process
2. Check the [open issues](https://github.com/Spark-Analytics-Demos/spark-retail-pack/issues) to avoid duplicate work
3. For anything larger than a bug fix, open an issue first to discuss approach

---

## License

| Directory | License |
|---|---|
| `02_dbt_core/` | [MIT](./02_dbt_core/LICENSE) |
| `05_demo_data/` | [MIT](./02_dbt_core/LICENSE) |
| Pro tier (macros, intermediate layer, `03_dbt_pro/`, dashboards, design docs) | Commercial license — contact Spark Analytics |

---

## Maintained by

**Spark Analytics** — [sparkanalytics.co.ke](https://sparkanalytics.co.ke)

Commercial inquiries: [info@sparkanalytics.co.ke](mailto:info@sparkanalytics.co.ke)

Technical questions: [open a GitHub issue](https://github.com/Spark-Analytics-Demos/spark-retail-pack/issues)
