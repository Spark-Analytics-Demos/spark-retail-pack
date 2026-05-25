# Section 12: Build Roadmap

> **Document status:** Draft v1
> **Audience:** Spark Analytics engineering team, leadership planning resourcing, contributors evaluating timeline, prospects asking "when does v1 ship?"
> **Purpose:** Sequence the build of the Spark Retail Pack into phases with effort estimates and dependencies. This section synthesizes the decisions made across Sections 1–11 into a project plan; it introduces no new design.

---

## 12.1 What this section defines

For the v1 build, this section specifies:

1. **The phased delivery plan** — what gets built when, with milestones
2. **Workstreams and ownership** — which team owns which deliverables
3. **Effort estimates per workstream** — in engineer-weeks
4. **Dependencies and critical path** — what must complete before what
5. **The MVP cutline** — what's in v1 vs. deferred to v1.x or v2
6. **Risks and contingencies** — what could slip and how it's managed

Where this section conflicts with another section, the other section wins. This document is a synthesis, not a re-specification.

---

## 12.2 Resourcing assumptions

The plan assumes a fixed team composition:

| Role | Headcount | Notes |
|---|---|---|
| Analytics engineer (lead) | 1.0 FTE | Owns canonical model, KPI implementation, dbt project |
| Analytics engineer (support) | 1.0 FTE | Owns connectors, staging, intermediate models |
| BI engineer | 0.5 FTE | Owns Power BI dashboards, semantic layer encoding |
| Data engineer | 0.5 FTE | Owns infrastructure, Snowflake setup, CI/CD |
| Product / design | 0.25 FTE | Dashboard design, demo scripts, sales materials |
| Engineering lead | 0.25 FTE | Architecture review, ADRs, sequencing |
| QA / testing | 0.25 FTE | Test framework, expected-values validation |

Total: ~3.75 FTE for the duration of v1 build. Most are Spark Analytics engineering team members; the BI engineer may be a contractor depending on availability.

This is the planning baseline. Real staffing will vary; the plan flexes by 20–30% in either direction without breaking.

---

## 12.3 Estimation philosophy

Effort estimates are in **engineer-weeks**, not calendar weeks. Calendar duration depends on parallel work, holidays, and unexpected interruptions.

For each workstream, the estimate covers:

- Design (already mostly done — captured in Sections 1–11)
- Implementation
- Testing (unit + integration + regression)
- Documentation
- Internal review and revision

Estimates are **deliberately rough**. Per-task estimates of 0.5 days would imply false precision; engineer-week granularity is honest about uncertainty.

Estimation method: each workstream lead provided a low/high range; mid-point is reported here. Total variance: roughly ±25% on each line. Cumulatively, expect the total v1 effort to land within ±15% of the headline figure (variances partially offset across many workstreams).

---

## 12.4 The phased plan

v1 ships in five phases over **~22 calendar weeks** (~5 months). Each phase has a definition of done and a demo-able artifact.

### Phase 0 — Foundation (weeks 1–3)

**Goal:** Snowflake account live, dbt project initialized, CI/CD running, basic source connections.

| Workstream | Owner | Effort (eng-weeks) |
|---|---|---|
| Snowflake account setup + role hierarchy (7 roles, Section 2.5) | Data engineer | 1.0 |
| dbt project scaffolding (OSS + Pro repos) | Lead AE | 1.0 |
| CI/CD pipeline (per Section 4 Part 3 §4.44) | Data engineer | 1.5 |
| Source connector configuration (Fivetran/Airbyte) — all 5 | Support AE | 2.0 |
| Bronze layer schema + permissions | Data engineer | 0.5 |
| Initial documentation site (dbt docs) | Lead AE | 0.5 |

**Phase 0 total:** ~6.5 engineer-weeks

**Demo-able at end:** A working dbt project that ingests Shopify data to bronze and runs `dbt build` successfully in CI.

### Phase 1 — Canonical core (weeks 3–9)

**Goal:** All 9 dimensions, all 9 facts, intermediate models, and the OSS macro library. The bulk of the OSS codebase.

| Workstream | Owner | Effort |
|---|---|---|
| Staging models — all 5 sources (Section 6) | Support AE | 4.0 |
| Intermediate models — identity resolution (ADR-003), FX, enrichment | Lead AE | 3.0 |
| 9 dimensions (Section 4 Part 1) | Lead AE | 4.0 |
| 9 facts (Section 4 Part 2) | Lead AE | 4.0 |
| 9 OSS macros (Section 4 Part 3 §4.47) | Lead AE | 2.0 |
| 8-column audit footer + lineage views | Support AE | 1.0 |
| Schema tests, business-rule tests (Section 4 Part 3 §4.37) | QA | 2.0 |
| Source freshness configuration | Support AE | 0.5 |

**Phase 1 total:** ~20.5 engineer-weeks

**Demo-able at end:** Full canonical model running on Shopify + Stripe demo data. `dim_customer` resolved across sources, `fact_orders` populated with all enrichment columns, audit columns on every table.

This is the **largest single phase** and the longest stretch of pure-engineering work in the project.

### Phase 2 — KPIs and semantic layer (weeks 9–14)

**Goal:** All 25 KPIs implemented, semantic layer encoded in MetricFlow, OSS-tier vs. Pro-tier split enforced.

| Workstream | Owner | Effort |
|---|---|---|
| 14 OSS KPIs — SQL implementation in marts | Lead AE | 3.0 |
| 11 Pro KPIs — SQL implementation in marts (proprietary repo) | Lead AE | 3.0 |
| 6 Pro macros (Section 4 Part 3 §4.47) | Lead AE | 2.0 |
| Semantic layer MetricFlow YAML (Section 7) — all 25 metrics | BI engineer | 3.0 |
| Business glossary (Section 7.11) | BI engineer | 0.5 |
| Entity ontology (Section 7.12) | BI engineer | 1.0 |
| AI metadata (synonyms, examples, domain facts) | BI engineer | 1.5 |
| Metric value tests (per Section 7.15) | QA | 1.5 |

**Phase 2 total:** ~15.5 engineer-weeks

**Demo-able at end:** Querying any of the 25 KPIs via dbt SL CLI returns correct values against demo data.

### Phase 3 — Dashboards and demo data (weeks 14–19)

**Goal:** Three production-grade Power BI dashboards connected to the semantic layer, demo dataset generated and validated.

| Workstream | Owner | Effort |
|---|---|---|
| Demo data generator (Section 9.6) — Python scripts, story modules | Lead AE + product | 4.0 |
| Medium tier dataset generated + validated | Lead AE | 1.0 |
| Expected KPI values file (Section 9.9) | QA | 1.5 |
| Power BI theme + style guide (Section 10.9) | Product / design | 1.5 |
| Dashboard 1 — Executive Summary (5 pages) | BI engineer | 3.0 |
| Dashboard 2 — Customer 360 (5 pages) | BI engineer | 3.5 |
| Dashboard 3 — Inventory Health (5 pages) | BI engineer | 3.0 |
| Cross-dashboard navigation (Section 10.13) | BI engineer | 0.5 |
| Performance optimization (Section 10.10 budgets) | BI engineer | 1.0 |

**Phase 3 total:** ~19 engineer-weeks

**Demo-able at end:** Prospect can open Power BI, see all three dashboards populated with Northwind Co. data, run the 5 story-arc demos.

### Phase 4 — Governance, hardening, and release (weeks 19–22)

**Goal:** Governance artifacts shipped, full documentation, packaging, and release.

| Workstream | Owner | Effort |
|---|---|---|
| Governance YAML artifacts (Section 8.12) — 8 files | Lead AE | 1.5 |
| PII handling end-to-end testing | QA | 1.0 |
| Erasure macro testing | QA | 0.5 |
| Implementation playbook (Section 11 Pro tier doc) | Lead + product | 2.0 |
| Sales playbooks — 5 demo scripts (Section 9.12) | Product | 1.5 |
| README + getting-started guides (OSS) | Lead AE | 1.0 |
| User-facing dashboard docs (Section 10.14) | Product | 1.0 |
| Release packaging — OSS GitHub release, Pro distribution | Lead | 1.0 |
| End-to-end smoke test on fresh client environment | QA + Lead | 1.5 |
| Buffer for late fixes and revisions | All | 2.5 |

**Phase 4 total:** ~13.5 engineer-weeks

**Demo-able at end:** v1 ships. OSS repo public on GitHub; Pro tier available for first pilot clients.

---

## 12.5 Total effort summary

| Phase | Eng-weeks | Calendar weeks | Cumulative calendar |
|---|---|---|---|
| Phase 0 — Foundation | 6.5 | 3 | 3 |
| Phase 1 — Canonical core | 20.5 | 6 | 9 |
| Phase 2 — KPIs + semantic layer | 15.5 | 5 | 14 |
| Phase 3 — Dashboards + demo data | 19 | 5 | 19 |
| Phase 4 — Governance, hardening, release | 13.5 | 3 | 22 |
| **Total** | **~75 engineer-weeks** | **~22 calendar weeks** | — |

The eng-weeks-to-calendar-weeks compression comes from parallel workstreams (e.g., during Phase 1, the support AE works on staging while the lead works on dimensions). The 3.75 FTE team can produce roughly 3.5 productive engineer-weeks per calendar week (after meetings, design discussion, code review).

---

## 12.6 Critical path

Some workstreams block downstream work; others run in parallel. The critical path determines minimum calendar duration regardless of resource availability.

**Critical path workstreams (cannot be shortened with more people):**

```
Snowflake setup (P0)
   ↓
dbt project scaffold (P0)
   ↓
Staging models — Shopify (P1)
   ↓
dim_customer + dim_product (P1)
   ↓
fact_orders + fact_order_lines (P1)
   ↓
OSS KPIs SQL (P2)
   ↓
MetricFlow YAML for Sales (P2)
   ↓
Executive Summary dashboard (P3)
   ↓
End-to-end smoke test (P4)
   ↓
Release
```

This chain is roughly 16 weeks of dedicated work. The parallel workstreams (other connectors, Customer 360 and Inventory dashboards, governance) fit around it.

If the team has only 1 FTE instead of 3.75, the calendar duration extends from 22 weeks to roughly 38 weeks — because the parallel workstreams must serialize behind the critical path.

---

## 12.7 Dependencies between sections

The build order respects natural data dependencies:

| Build sequence | Reason |
|---|---|
| Snowflake + dbt project before anything | Nothing runs without infrastructure |
| Staging before intermediate before core | Layered architecture per Section 2.2 |
| Shopify before other connectors | Shopify is the only connector required by all three modules (Section 6.11) |
| Dimensions before facts (mostly) | Facts FK to dimensions |
| Core before marts before semantic layer | Each layer depends on the prior |
| Semantic layer before dashboards | Dashboards consume via Semantic Layer (Section 10.7) |
| Demo data generator early in Phase 3 | Dashboards need data; expected values need generator output |
| Governance artifacts after core stable | Governance configs reference canonical column names |

A few decisions about **what NOT to wait for**:

- **GA4 connector** doesn't block Sales dashboards (Sales doesn't need sessions)
- **Klaviyo** doesn't block until late Phase 3 (only Customer 360 needs it)
- **Meta Ads** doesn't block until Phase 3 (only Customer 360 needs it)
- **Inventory connector work** can parallel customer work — different schemas, different SMEs

This is why parallelism is achievable: not everything depends on everything.

---

## 12.8 The MVP cutline

Throughout the design, scope discipline was maintained. Section 1.5 set the MVP scope; every later section has either honored it or explicitly deferred features.

### What's in v1 (recap)

- 3 modules: Sales Analytics, Customer 360, Inventory Health
- 25 KPIs (14 OSS, 11 Pro)
- 5 source connectors: Shopify, Stripe, GA4, Meta Ads, Klaviyo
- 9 dimensions, 9 facts
- Semantic layer with MetricFlow encoding for all 25 KPIs
- 3 Power BI dashboards (Executive Summary, Customer 360, Inventory Health)
- Synthetic demo data (Northwind Co.) at 3 tiers
- Governance baseline (ownership, classification, PII handling, audit, retention, erasure)
- 9 OSS macros + 6 Pro macros
- Snowflake + dbt Core + Power BI + MetricFlow stack

### What's deliberately NOT in v1

Consolidated from earlier sections' deferred-to-v2 lists:

| Feature | Deferred to | Section that flagged it |
|---|---|---|
| Marketing Attribution module (multi-touch) | v2 | §3.8 |
| Customer Service / Support module | v2 | §3.8 |
| Fulfillment / Logistics module | v2 | §3.8 |
| Subscription / Recurring Revenue module | v2 | §3.8, §9.11 |
| Google Ads connector | v2 | §6.9 |
| TikTok Ads connector | v2 | §6.9 |
| Amazon Seller Central connector | v2 | §6.9 |
| Zendesk / Gorgias connector | v2 | §6.9 |
| Recharge subscription connector | v2 | §6.9 |
| Smile.io / loyalty connectors | v2 | §6.9 |
| QuickBooks / NetSuite finance connectors | v2 | §6.9 |
| Real-time / streaming pipelines | v2 | §7.16 |
| AI assistant (natural-language querying) | v2 | §7.14 |
| Embedded analytics (white-label) | v2 | §7.14, §10.15 |
| Mobile-optimized dashboards | v2 | §10.15 |
| Multi-warehouse support (BigQuery, Databricks) | v2 | §11.8 |
| Looker / Tableau / Metabase equivalents | v2 | §11.8 |
| ML-based predictive metrics (predicted LTV, churn probability) | v2 | §11.8 |
| B2B / wholesale variant | v2 | §11.8 |
| SOC 2 / ISO 27001 certification | Not pursued in v1 | §8.13 |
| Customer-managed encryption keys (CMK / BYOK) | v2 | §8.13 |
| Differential privacy beyond hashing | v2 | §8.13 |
| Multi-currency dashboard variants | v2 | §10.15 |
| Non-English dashboards | v2 | §10.15 |
| Cumulative metrics (running totals) | v2 | §7.16 |
| Conversion / funnel metrics | v2 | §7.16 |
| Row-level security at semantic layer | v2 | §7.16 |

This is a long list — and that's the point. Every "no" is documented with the section that scoped it out. The MVP got smaller deliberately so it could ship.

### What v1.x might pick up before v2

Some items are too small for a full v2 cycle but valuable enough that they might land in a v1.x patch:

- Additional language for the dashboard pack (Spanish first, French second)
- Configurable retention policies in `06_governance/retention.yml` exposed more cleanly
- Small dashboard polish based on first-client feedback
- Bug fixes from production deployments

v1.x patches will be released as needed; no fixed cadence in v1.

---

## 12.9 Resourcing the parallel work

For the 22-week calendar plan to work, parallel work must actually parallelize. The week-by-week breakdown:

| Week | Lead AE | Support AE | BI Eng | Data Eng |
|---|---|---|---|---|
| 1–3 | Project scaffold | Source connector config | Setup, theme research | Snowflake + CI/CD |
| 4–6 | Staging Shopify, Stripe | Staging GA4, Meta, Klaviyo | Theme design | dbt orchestration |
| 7–9 | Dimensions (5 of 9) | Dimensions (4 of 9) | Theme finalize | Source freshness |
| 9–11 | Facts (5 of 9) | Facts (4 of 9) | MetricFlow YAML Sales | Cost monitoring |
| 12–14 | OSS KPIs SQL | Pro KPIs SQL | MetricFlow YAML Customer, Inventory | Performance tuning |
| 15–17 | Demo data generator | Pro macros | Dashboard 1 — Exec | Snowflake optimization |
| 18–19 | Expected values + validation | Story modules | Dashboards 2, 3 | — |
| 20–22 | Governance, docs | Hardening | Final dashboard polish | Production readiness |

This grid assumes no one is sick, no holidays, no scope changes. Real execution will diverge; the plan provides the target.

---

## 12.10 Milestones and quality gates

Each phase has a hard exit criterion. Failing the criterion delays the phase rather than carrying technical debt forward.

| Phase | Quality gate | Pass / fail criteria |
|---|---|---|
| 0 | `dbt build` succeeds in CI | All Shopify staging models build green |
| 1 | All canonical models validate | All schema tests pass, no failed business-rule tests, no broken references |
| 2 | All 25 KPIs return correct values | KPI values match expected values per Section 9.9 with 0 absolute / 0.5% ratio tolerance |
| 3 | All 3 dashboards meet performance budgets | Load <5s, slicer <2s, drill <3s per Section 10.10 |
| 4 | First-client smoke test passes | A net-new environment can be set up and produce correct dashboards in <8 hours |

If a quality gate fails, the team fixes the underlying issue before proceeding. This is more honest than "carry the bug forward and fix later" — bugs compound across layers.

---

## 12.11 Risk register

The five biggest risks to the v1 timeline and how each is managed.

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| **Power BI Semantic Layer connector limitations** (per §10.7) — Pro tier may not work cleanly without dbt Cloud | Medium | High | Resolved via [ADR-004](../07_decisions/ADR-004-dbt-core-vs-cloud-semantic-layer.md): two-path strategy (Path 1 dbt Cloud, Path 2 dbt Core fallback) documented in implementation playbook |
| **Demo data generator complexity** — Stories may be harder to embed realistically than estimated | Medium | Medium | Phase 3 budget includes 4 eng-weeks for generator; can scope down stories from 5 to 3 if needed |
| **dbt Semantic Layer feature gaps** — MetricFlow may not support every needed pattern (non-additivity edge cases, etc.) | Low | Medium | Section 7.16 already lists deferred features; v1 ships what works, defers what doesn't |
| **First client implementation friction** — first paying client may surface integration issues not in synthetic data | High | Medium | Phase 4 includes a smoke-test workstream; first 2 clients are positioned as "pilot" with explicit feedback loops |
| **Scope creep from prospect feedback** — sales conversations may pressure adding "just one more" feature | High | High | Section 1.5 MVP scope is the contract; every addition requires explicit roadmap review and trades against existing scope |

These are the risks the engineering lead actively tracks; minor risks are managed within phases.

---

## 12.12 Post-v1 roadmap

Beyond v1, the next 12–18 months target:

### v1.1 — v1.3 patches (months 6–10)

- First-client feedback incorporation
- Performance optimization based on real workloads
- Documentation improvements from community contribution

### v2.0 (months 10–18)

The big-feature release. Likely scope:

- 2–3 new modules from §3.8 (Marketing Attribution, Customer Service, Fulfillment)
- 4–6 new connectors from §6.9 (Google Ads, TikTok, Amazon, Zendesk)
- AI assistant feature (built on Section 7's semantic layer)
- Mobile-optimized dashboards
- BigQuery or Databricks support (one warehouse beyond Snowflake)
- Embedded analytics MVP (white-label)

Pricing for v2 features is a separate decision — early-adopter discounting, included-in-existing-license vs. new-tier, etc. — outside this section's scope.

### v3.0+ (year 2+)

Beyond v2 is speculative. Categories under consideration:

- Industry adjacencies: Beauty, Food & Beverage, Home & Garden specific extensions
- B2B / wholesale variant
- ML-based predictive metrics
- Multi-language dashboards
- SOC 2 certification of the pack itself

These aren't promises — they're directions. The product roadmap evolves with client demand signals.

---

## 12.13 What happens after v1 ships

The day v1 ships is the start of a different kind of work:

| Activity | Owner | Cadence |
|---|---|---|
| OSS community management (GitHub issues, PRs) | Lead AE | Daily |
| First-client implementation engagements | Services team | Per client |
| Bug fixes and patches | Engineering | As-needed |
| Documentation updates from real-world questions | Product | Weekly |
| Sales material refresh based on what works | Product | Monthly |
| Quarterly product review with paying clients | Leadership | Quarterly |
| v2 feature scoping based on client demand | Product + Eng lead | Quarterly |

The product transitions from "design and build" mode to "operate and improve" mode. Section 13 (currently a placeholder) will document the operational practices for this mode in detail.

---

## 12.14 Summary

The Spark Retail Pack v1 builds in **5 phases over 22 calendar weeks**, requiring **~75 engineer-weeks** of total effort distributed across a ~3.75 FTE team.

The build sequence respects data dependencies (foundation → core → marts → semantic → consumption), with parallel workstreams compressing eng-weeks into calendar-weeks.

The MVP cutline is **defended** — 27 distinct features were explicitly deferred to v2 (or not pursued in v1) across earlier sections, and each "no" is documented with the section that scoped it out.

Quality gates at the end of each phase prevent technical debt from accumulating across layers. Risk management focuses on five identified risks; the biggest is the dbt Cloud vs. dbt Core ambiguity for the Semantic Layer, now resolved via [ADR-004](../07_decisions/ADR-004-dbt-core-vs-cloud-semantic-layer.md).

After v1, the product transitions from build mode to operate mode. v1.x patches address first-client feedback; v2 in months 10–18 adds the big-feature increment.

Section 13 (operational best practices) covers what happens after release — support tiers, capacity planning, security operations, training. It's currently a placeholder and will be the final section of the design document.

---

**Previous:** [Section 11: Open-Source vs. Pro Split](./11_open_source_vs_pro_split.md)
**Next:** [Section 13: Operational Best Practices](./13_operational_best_practices.md)
