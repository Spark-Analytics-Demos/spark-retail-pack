# Design Documents

This folder contains the complete design specification for the Spark Retail Pack v1.

The design document is broken into focused sections that build on each other. Read them in order — later sections reference decisions made in earlier ones.

---

## Table of contents

| # | Document | Status | Purpose |
|---|---|---|---|
| 01 | [Executive Overview](./01_executive_overview.md) | ✅ Complete | What the pack is, who it's for, scope |
| 02 | [Architecture](./02_architecture.md) | ✅ Complete | Layered architecture, tech stack, data flow |
| 03 | [Module Breakdown](./03_module_breakdown.md) | ✅ Complete | Sales Analytics, Customer 360, Inventory Health |
| 04 | Canonical Data Model — [Part 1: Dimensions](./04_canonical_data_model_part1_dimensions.md) / [Part 2: Facts](./04_canonical_data_model_part2_facts.md) / [Part 3: Implementation Standards](./04_canonical_data_model_part3_implementation_standards.md) | ✅ Complete | All dimensions, facts, and engineering standards |
| 05 | [KPI Catalog](./05_kpi_catalog.md) | ✅ Complete | 25 KPIs with formulas, grain, ownership |
| 06 | [Connector Specs](./06_connector_specs.md) | ✅ Complete | Source-to-canonical mappings for 5 connectors |
| 07 | [Semantic Layer](./07_semantic_layer.md) | ✅ Complete | Metric definitions, business glossary, ontology |
| 08 | [Governance Baseline](./08_governance_baseline.md) | ✅ Complete | Ownership, classification, PII handling |
| 09 | [Demo Data Design](./09_demo_data_design.md) | ✅ Complete | Story arc, scale, generation approach |
| 10 | [Power BI Dashboard Pack](./10_powerbi_dashboard_pack.md) | ✅ Complete | 3 dashboards, drill-down patterns |
| 11 | [Open-Source vs. Pro Split](./11_open_source_vs_pro_split.md) | ✅ Complete | Exactly what goes where |
| 12 | [Build Roadmap](./12_build_roadmap.md) | ✅ Complete | Sequencing and effort estimates |
| 13 | [Operational Best Practices](./13_operational_best_practices.md) | ✅ Complete | Deployment, support, upgrades, training, engagement model |

---

## Supporting materials

- `diagrams/` — architecture diagrams, ERDs, data flow visuals (created as we go)

---

## Document conventions

- All documents are in Markdown for easy version control and readability.
- Diagrams use Mermaid syntax where possible (renders natively in GitHub and most modern editors).
- Code examples use SQL or YAML.
- Decisions that affect multiple sections are captured as ADRs in `../07_decisions/`.
