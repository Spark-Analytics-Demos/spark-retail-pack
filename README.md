# Spark Retail Pack

> **A productized data warehouse accelerator for direct-to-consumer retail and e-commerce.**
> Built on Snowflake + dbt + Power BI. Open-core distribution.

[![Status: Phase 0](https://img.shields.io/badge/status-Phase%200%20Foundation-yellow)]()
[![Design: Complete](https://img.shields.io/badge/design-v1%20complete-green)]()
[![License: TBD](https://img.shields.io/badge/license-MIT%20%2B%20commercial-blue)]()

---

## What this is

The Spark Retail Pack lets a mid-market direct-to-consumer retailer ($5M–$200M GMV) stand up a fully modeled, governed, AI-ready analytics warehouse in **4–6 weeks** instead of 6+ months — and then iterate on it as a product rather than rebuild it as a project.

It ships as three things working together:

- **Open-source core** (MIT) — the entire canonical data model, 5 source connectors, 14 KPIs, governance machinery, and a deterministic demo data generator. Free, forever.
- **Proprietary modules** (commercial license) — the semantic layer encoding, 3 Power BI dashboard packs, 11 additional KPIs, advanced macros (LTV, attribution, cohorts), and AI-ready metadata.
- **Implementation services** — Spark Analytics' 4–6 week deployment engagements, custom development, and ongoing managed service.

---

## What's in here

```
Retail_Pack/
├── 01_design_docs/        ← Complete v1 design specification (13 sections + 4 ADRs)
├── 02_dbt_core/           ← Open-source dbt project (MIT-licensed at publish)
├── 03_dbt_pro/            ← Proprietary dbt project (commercial license)
├── 04_dashboards/         ← Power BI .pbix files (proprietary)
├── 05_demo_data/          ← Northwind Co. synthetic data generator
├── 06_governance/         ← Governance YAML artifacts
├── 07_decisions/          ← Architecture Decision Records (ADRs)
├── CLAUDE.md              ← Project context for AI coding assistants
├── CONTRIBUTING.md        ← Open-core contribution guide
└── PHASE_0_CHECKLIST.md   ← Current-phase build checklist
```

For the table of contents of the design document, see [`01_design_docs/README.md`](./01_design_docs/README.md).

---

## Status

- ✅ **Design phase complete** — Sections 1–13 drafted; ADRs 001–004 accepted
- 🏗️ **Build phase: Phase 0 (Foundation)** — scaffolding in place, infrastructure provisioning underway
- ⏳ **Target v1 ship:** ~22 weeks from Phase 0 start (per [`12_build_roadmap.md`](./01_design_docs/12_build_roadmap.md))

This is an **early-stage** repository. v1 has not yet shipped. Substantial contributions are best discussed via issue first.

---

## Tech stack

| Layer | Choice |
|---|---|
| Cloud data warehouse | Snowflake |
| Transformation framework | dbt Core |
| Business intelligence | Power BI |
| Semantic layer | dbt Semantic Layer (MetricFlow) — see [ADR-004](./07_decisions/ADR-004-dbt-core-vs-cloud-semantic-layer.md) for the two-path access model |
| Distribution | Hybrid open-core (MIT core + commercial Pro) |

Tech choices are locked per [ADR-001](./07_decisions/ADR-001-initial-tech-stack.md). Multi-warehouse support (BigQuery, Databricks) is on the v2 roadmap.

---

## What you can do with the OSS core (when published)

The open-source core ships everything you need to stand up the canonical warehouse:

- All 9 dimensions and 9 facts modeling the D2C retail business
- Staging models for **Shopify, Stripe, Google Analytics 4, Meta Ads, and Klaviyo**
- Identity resolution across sources with three-tier fuzzy matching
- 14 production-grade KPIs (GMV, AOV, retention, stockouts, more)
- 8-column audit footer on every table with full lineage
- PII handling with masking-by-default and a GDPR/CCPA erasure macro
- Deterministic synthetic data generator (Northwind Co. fictional retailer with 5 embedded business scenarios)
- CI/CD-ready dbt project with comprehensive test framework

Use it to build your own dashboards, your own semantic layer, your own AI integration — or upgrade to the Pro tier and get those out of the box.

---

## What the Pro tier adds

The Pro tier (commercial license, annual subscription) adds:

- **3 Power BI dashboard packs** (Executive Summary, Customer 360, Inventory Health — 5 pages each)
- **Semantic layer encoding** for all 25 KPIs in MetricFlow YAML, plus business glossary and entity ontology
- **11 advanced KPIs** — Customer Lifetime Value, CAC by channel, ROAS, cohort sell-through, inventory turnover, more
- **6 proprietary macros** — RFM segmentation, cohort retention, first-touch and last-touch attribution, churn risk, inventory velocity flags
- **AI-ready metadata** — synonyms, example queries, domain knowledge facts for natural-language querying
- **Implementation playbook** and sales-ready demo scripts

See [`11_open_source_vs_pro_split.md`](./01_design_docs/11_open_source_vs_pro_split.md) for the full component-by-component split.

---

## Documentation

| Topic | Where |
|---|---|
| **What this product is and who it's for** | [`01_executive_overview.md`](./01_design_docs/01_executive_overview.md) |
| **Architecture and tech stack** | [`02_architecture.md`](./01_design_docs/02_architecture.md) |
| **Canonical data model** | [`04_canonical_data_model_*.md`](./01_design_docs/) (3 parts) |
| **KPI catalog (all 25)** | [`05_kpi_catalog.md`](./01_design_docs/05_kpi_catalog.md) |
| **Connector specifications** | [`06_connector_specs.md`](./01_design_docs/06_connector_specs.md) |
| **Semantic layer design** | [`07_semantic_layer.md`](./01_design_docs/07_semantic_layer.md) |
| **Governance baseline** | [`08_governance_baseline.md`](./01_design_docs/08_governance_baseline.md) |
| **Build roadmap and effort estimates** | [`12_build_roadmap.md`](./01_design_docs/12_build_roadmap.md) |
| **Operations and support** | [`13_operational_best_practices.md`](./01_design_docs/13_operational_best_practices.md) |

---

## Contributing

Contributions to the open-source core (`02_dbt_core/`) are welcome under our CLA. See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for details on:

- What contributions are accepted (and what aren't)
- Code style and conventions
- The CLA signing process
- Local development setup

The proprietary modules are not open for external contributions.

---

## License

- **`02_dbt_core/`** — MIT License (when published)
- **`03_dbt_pro/`**, **`04_dashboards/`** — commercial license (terms TBD)
- **Design documents** (`01_design_docs/`) — internal documentation; license TBD at publish

Until v1 ships and the OSS/Pro split is formalized in code, the entire repository is private and unlicensed for external use.

---

## Maintained by

[Spark Analytics](https://example.com) — Data Consultancy

For commercial inquiries: [contact@example.com](mailto:contact@example.com)

For technical questions: open a GitHub Issue or join our Discord (link TBD)
