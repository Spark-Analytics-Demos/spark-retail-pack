# ADR-004: dbt Core vs. dbt Cloud for Semantic Layer Access

**Status:** Accepted
**Date:** 2026-05-14
**Deciders:** Spark Analytics leadership, engineering lead
**Supersedes:** N/A
**Superseded by:** N/A
**Related:** ADR-001 (Initial Tech Stack), Section 7 (Semantic Layer), Section 10.7 (Connection Model)

---

## Context

ADR-001 selected **dbt Core** as the transformation framework and **dbt Semantic Layer (MetricFlow)** as the metrics layer. At the time, this was framed as a single decision — "use dbt's metrics tooling."

During Section 10 (Power BI Dashboard Pack) design, a real architectural ambiguity surfaced that ADR-001 didn't address:

**The dbt Semantic Layer has two parts:**

1. **Authoring layer** — MetricFlow YAML definitions, the compiler, the CLI for local querying. This is part of **dbt Core**, free and open source.
2. **GraphQL API** — the runtime endpoint that BI tools and AI assistants query to compute metrics on demand. This is part of **dbt Cloud** (Team or Enterprise tier), commercial and paid.

The pack's architecture (Sections 7 and 10) assumes Power BI connects to the GraphQL API to query metrics. But that API is **not available with dbt Core alone**. Authoring MetricFlow definitions is free; serving them to consumers via the standard connector path requires dbt Cloud.

This affects:
- **Clients running dbt Core without dbt Cloud** — they have MetricFlow YAML but no API for Power BI to call
- **Pricing** — dbt Cloud Team tier is ~$100/seat/month at time of writing, which adds a meaningful cost to deployments
- **Open-core positioning** — if the proprietary tier requires another vendor's paid product to function, that's a real adoption friction

The question is **not whether to use MetricFlow** (ADR-001 stands), but **how to handle clients along the dbt Cloud vs. Core spectrum**.

---

## Options considered

### Option A: Require dbt Cloud for all Pro deployments

Mandate dbt Cloud Team tier as a Pro tier prerequisite. Power BI connects to the Semantic Layer GraphQL API; the architecture is clean.

**Pros:**
- Single architectural path; simpler to design, document, and support
- Best Power BI experience (metric consistency, drill-through, AI integration)
- Aligns with how dbt Labs intends the Semantic Layer to be consumed
- Section 7 and 10's designs work as written without modification

**Cons:**
- Forces every paying client into an additional vendor relationship
- ~$100/seat/month dbt Cloud cost may be material for smaller mid-market clients (the lower end of our $5–25M GMV tier)
- "Open core" claim weakens — the proprietary tier depends on another company's paid product
- A client running dbt Core perfectly happily for transformation is now told they need dbt Cloud too

### Option B: Build our own metrics API in front of dbt Core

Materialize all metrics from MetricFlow YAML into Snowflake views; expose those via a Spark-built API layer (e.g., a thin GraphQL service the pack ships).

**Pros:**
- No dbt Cloud dependency
- Full control over the metrics API
- Could add Spark-specific features (caching, custom auth, embedded tenancy)

**Cons:**
- Significant engineering effort (estimated 8–12 engineer-weeks for v1)
- Introduces a Spark-built component on the critical path between Snowflake and Power BI
- We become responsible for an API tier's reliability, scalability, observability
- Reinvents what dbt Labs has already built; we'd be a worse version of it
- Distracts from the actual product (retail-specific dashboards and KPIs)

### Option C: Support two paths — dbt Cloud (recommended) OR materialized fallback

Document and support both:
- **Path 1 (recommended for production):** Client runs on dbt Cloud. Power BI connects to the Semantic Layer GraphQL API. Single source of truth at runtime; full feature set.
- **Path 2 (fallback for budget-constrained or evaluation deployments):** Metrics from MetricFlow YAML materialize to mart views in Snowflake. Power BI connects to Snowflake directly. Some metrics computed in DAX rather than via the API; metric consistency across consumers (Power BI, AI assistant, ad-hoc SQL) is no longer guaranteed by the architecture.

**Pros:**
- Clients self-select based on their budget and sophistication
- "Open core" claim holds — a free-tier client can use OSS dbt Core and Snowflake direct connection without dbt Cloud
- No proprietary API to build
- Section 7's MetricFlow YAML authoring stays valuable in both paths
- Production-grade clients get the clean Path 1; evaluation and budget clients get Path 2

**Cons:**
- Two paths to document, test, and support
- Path 2 loses the single-source-of-truth metric consistency
- A client starting on Path 2 has to migrate later to Path 1 for full Pro features
- Some Pro tier features (AI assistant, embedded analytics, drill-through across dashboards) work better on Path 1; documenting which-feature-on-which-path adds complexity

### Option D: Migrate to a different metrics tool (e.g., Cube, MetricFlow open-source fork)

Abandon dbt Semantic Layer; use an alternative.

**Pros:**
- Removes the dbt Cloud dependency entirely
- Open-source alternatives exist (Cube, AtScale Open, MetricFlow forks)

**Cons:**
- Throws away ADR-001's reasoning (the dbt ecosystem alignment)
- Each alternative has its own constraints and vendor lock-in
- Migration cost is high — Section 7's YAML would need rewriting
- The dbt Semantic Layer is the industry's emerging standard; betting against it is a strategic risk

---

## Decision

**Option C: Support two paths — dbt Cloud (recommended) OR materialized fallback.**

The pack documents both paths as legitimate. Path 1 (dbt Cloud) is the recommended production path; Path 2 (materialized fallback) is the supported alternative for budget-constrained or evaluation deployments.

The MetricFlow YAML defined in Section 7 is authored once and consumable both ways:

- Path 1 reads it at runtime via the dbt Cloud Semantic Layer API
- Path 2 uses it as a source-of-truth specification but materializes metrics to Snowflake views that Power BI reads directly

---

## Consequences

### Implementation

- **Phase 2** (per Section 12.4) implements MetricFlow YAML once
- **Phase 3** implements Power BI dashboards for **Path 1 as default**, with Path 2 fallback dataset configurations documented in `04_dashboards/INSTALLATION.md`
- A small materialization helper macro (`materialize_metric_from_semantic_yaml`) is added to the Pro macro set (Section 4 Part 3 §4.47), which compiles a MetricFlow metric definition into a Snowflake view. Estimated effort: 1 engineer-week (subsumed within Phase 2's BI engineering budget).

### Client implementation playbook

The Pro tier implementation engagement adds a Phase 0 decision point: **dbt Cloud or dbt Core only?** This becomes one of the first 5 questions in client kickoff.

| Client situation | Recommendation |
|---|---|
| Already on dbt Cloud | Stay on Path 1 |
| Already on dbt Core, no Cloud budget | Start on Path 2; migrate to Path 1 in v1.x if needed |
| Greenfield with budget for Cloud | Path 1 from day one |
| Greenfield, evaluating | Path 2 for evaluation; revisit at production cutover |
| Enterprise with strict vendor policies | Case-by-case; sometimes Path 2 is required |

### Feature impact

Some features depend on Path 1 (the API):

| Feature | Path 1 (Cloud) | Path 2 (Fallback) |
|---|---|---|
| 25 KPIs queryable | ✅ All via API | ✅ All via materialized views |
| Power BI dashboards | ✅ Full functionality | ✅ Works, but metrics computed in dataset layer |
| Cross-dashboard metric consistency | ✅ Guaranteed by API | ⚠️ Best-effort via DAX discipline |
| AI assistant (v2) | ✅ Designed for the API | ⚠️ Requires custom adapter to query views |
| Embedded analytics (v2) | ✅ API has tenant filters | ⚠️ Tenant filtering becomes a Power BI RLS concern |
| Ad-hoc SQL on metrics | ✅ Via dbt SL CLI | ✅ Direct SQL on views |

This trade-off is **disclosed upfront** in the implementation playbook so clients choose with eyes open.

### Pricing impact

Path 2 reduces the total cost of ownership for budget-constrained clients (no dbt Cloud subscription). Spark Analytics Pro tier pricing (Section 11.5) stays the same regardless of path — we're not in the business of selling dbt Cloud, but we're also not discounting our Pro tier for clients who pay less elsewhere.

### Open-core positioning

This decision **strengthens** the open-core claim. A free-tier client running OSS dbt Core can theoretically also adopt Path 2's materialization pattern to build their own dashboards — though without the proprietary dashboards, semantic encoding YAML, and AI metadata that make Pro tier valuable. The architectural choice doesn't degrade the OSS tier.

### Documentation burden

Two paths means more documentation, more test coverage, and more support scenarios. The Phase 4 documentation budget (Section 12.4) absorbs this; estimated additional load is ~1.5 engineer-weeks for path-specific guides.

### Future migration

If dbt Labs introduces a free or low-cost tier of the Semantic Layer API (a real possibility given competitive pressure from Cube and others), this ADR may be revisited. The Path 2 fallback becomes less necessary if Path 1 cost drops. ADR-005 (hypothetical) would document such a revisit.

### Risk reduction

The ambiguity flagged in Section 10.11's risk register ("Power BI Semantic Layer connector limitations") is now resolved — not by eliminating the risk, but by documenting it as a managed trade-off rather than an unmitigated one.

---

## Implementation checklist

- [ ] Section 7.3 (Tool choice) updated to acknowledge the two paths
- [ ] Section 10.7 (Connection model) — already updated during Section 10 QA to flag the trade-off; cross-reference this ADR
- [ ] Section 11.6 (Strategic case) updated to note that Path 2 is a supported deployment option
- [ ] Section 12.4 Phase 2 budget includes the materialization helper macro
- [ ] Implementation playbook (Pro tier doc) adds the dbt Cloud vs. Core decision question
- [ ] `04_dashboards/INSTALLATION.md` documents both connection patterns
- [ ] Section 10's risk register updated to mark this risk as Resolved-via-ADR-004

These updates are not blocking; they happen during Phase 2 (per the build roadmap).

---

## Notes for future ADRs

Two related architectural decisions are likely to come up in v1.x or v2 and would warrant their own ADRs:

- **ADR-005 (hypothetical):** Multi-warehouse support — if v2 adds BigQuery or Databricks, the Semantic Layer needs to remain warehouse-agnostic. Path 2's materialization approach is more portable than Path 1's API; this might bias future decisions.
- **ADR-006 (hypothetical):** AI assistant API contract — when the AI assistant ships (v2), it needs a stable API to query. ADR-004's two paths complicate this; ADR-006 would specify whether the AI assistant supports both paths or only Path 1.

Documenting these here so future ADRs don't have to rediscover the context.
