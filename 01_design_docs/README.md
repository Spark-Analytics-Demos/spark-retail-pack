# Spark Retail Pack — Design Documents

v1 design specification. All sections are **draft-complete**. The design is the source of truth; code follows it.

| File | Section | Topic |
|---|---|---|
| [01_executive_overview.md](./01_executive_overview.md) | 1 | Why we're building this, target client, MVP scope |
| [02_architecture.md](./02_architecture.md) | 2 | Snowflake setup, database/schema layout, 7-role hierarchy |
| [03_module_breakdown.md](./03_module_breakdown.md) | 3 | Sales Analytics, Customer 360, Inventory Health module specs |
| [04_canonical_data_model_part1_dimensions.md](./04_canonical_data_model_part1_dimensions.md) | 4.1 | 9 dimensions — schema, grain, SCD2 strategy |
| [04_canonical_data_model_part2_facts.md](./04_canonical_data_model_part2_facts.md) | 4.2 | 9 facts — schema, grain, incremental strategy, audit footer |
| [04_canonical_data_model_part3_implementation_standards.md](./04_canonical_data_model_part3_implementation_standards.md) | 4.3 | Materialization defaults, macros, tests, CI/CD, versioning |
| [05_kpi_catalog.md](./05_kpi_catalog.md) | 5 | 25 KPIs (14 OSS + 11 Pro) — definitions, SQL logic, tier |
| [06_connector_specs.md](./06_connector_specs.md) | 6 | Shopify, Stripe, GA4, Meta Ads, Klaviyo connector specs |
| [07_semantic_layer.md](./07_semantic_layer.md) | 7 | MetricFlow YAML, business glossary, entity ontology, AI metadata |
| [08_governance_baseline.md](./08_governance_baseline.md) | 8 | PII, access control, audit trail, lineage, retention, erasure |
| [09_demo_data_design.md](./09_demo_data_design.md) | 9 | Northwind Co. persona, story arcs, generator design |
| [10_powerbi_dashboard_pack.md](./10_powerbi_dashboard_pack.md) | 10 | 3 dashboards, 15 pages, performance budgets, style guide |
| [11_open_source_vs_pro_split.md](./11_open_source_vs_pro_split.md) | 11 | OSS/Pro boundary — what's MIT, what's commercial |
| [12_build_roadmap.md](./12_build_roadmap.md) | 12 | 5-phase plan, effort estimates, critical path, risks |
| [13_operational_best_practices.md](./13_operational_best_practices.md) | 13 | Post-v1 operations — support, capacity, security |

## Architecture decisions

ADRs live in `../07_decisions/`. Each records a significant decision, the options considered, and the rationale.

| File | Decision |
|---|---|
| [ADR-001](../07_decisions/ADR-001-initial-tech-stack.md) | Initial tech stack (Snowflake + dbt Core + Power BI) |
| [ADR-002](../07_decisions/ADR-002-audit-and-lineage.md) | Audit and lineage approach |
| [ADR-003](../07_decisions/ADR-003-fuzzy-identity-resolution.md) | Fuzzy identity resolution strategy |
| [ADR-004](../07_decisions/ADR-004-dbt-core-vs-cloud-semantic-layer.md) | dbt Core vs. Cloud for Semantic Layer access |

## Reading order for new contributors

1. Start with **Section 1** (executive overview) for the "why"
2. Read **Section 2** (architecture) to understand the Snowflake layout
3. Read **Section 4** (canonical model, all three parts) before writing any SQL
4. Read **Section 11** (OSS/Pro split) before adding any model — know which repo it belongs in
5. Check **Section 12** (roadmap) to understand what phase you're in and what's in scope
