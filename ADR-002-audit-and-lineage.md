# ADR-002: Audit and Lineage Column Architecture

**Status:** Accepted
**Date:** 2026-05-13
**Deciders:** Spark Analytics leadership
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

The initial canonical data model (Section 4 Parts 1 and 2) defined dimensions and facts with the business columns required for analytics. During design review, a critical gap was identified: **no rows in the canonical model could be traced back to their origin, the dbt run that produced them, or the time they were extracted from source.**

This creates concrete problems for enterprise clients:

- When a KPI looks wrong, an engineer must manually trace it through staging, intermediate, and source tables to find the root cause. This often takes hours.
- When a dbt run causes bad data, there is no way to identify and roll back just the rows affected by that run — the whole table must be rebuilt.
- When clients ask "is our data fresh?", there is no programmatic answer beyond looking at `loaded_at` on the latest row.
- Enterprise procurement processes increasingly require demonstrable audit trails. Without them, the pack is non-viable for clients in regulated industries or those with mature data governance practices.

This problem must be solved before the pack is buildable. Retrofitting audit columns onto a built warehouse is significantly harder than building them in from the start.

---

## Options considered

### Option A: Minimal audit (just `loaded_at`)

Keep what the initial design had. Add nothing else.

**Pros:** Simple. Already designed.
**Cons:** Doesn't solve the actual problems. No source traceability, no run-level rollback, no change detection.

### Option B: Standard audit footer (8 columns per table)

Every table carries: `_source_system`, `_source_record_id`, `_extracted_at`, `_loaded_at`, `_dbt_invocation_id`, `_dbt_model`, `_record_hash`, `_is_deleted_at_source`.

Populated automatically by a single macro called at the end of every model.

**Pros:** Comprehensive. Standard pattern across modern data warehouses (used by every mature analytics engineering team). Each column has a clear, distinct purpose. Storage cost is negligible due to columnar compression.
**Cons:** Eight extra columns per table feels heavy at first glance. Requires a macro pattern that all model authors must follow.

### Option C: Audit columns in a separate sidecar table

Keep business columns clean. Maintain a parallel `<table>_audit` for each table.

**Pros:** Business tables stay narrow.
**Cons:** Requires a join for every audit query. Doubles the number of tables. Hard to keep in sync. Industry practice has moved away from this pattern.

### Option D: Row-level audit via Snowflake's `INFORMATION_SCHEMA` and `ACCESS_HISTORY`

Rely on Snowflake's native query history and access tracking instead of building our own.

**Pros:** No custom columns needed. Snowflake handles it.
**Cons:** `INFORMATION_SCHEMA` doesn't track row-level provenance — only object-level access. `ACCESS_HISTORY` is also access-level, not row-level. Doesn't answer "which dbt run produced this row." Doesn't work outside Snowflake (when the pack eventually supports BigQuery/Databricks). Doesn't help with source extraction lag.

---

## Decision

**Option B: Standard audit footer of 8 columns on every table, populated by a single `add_audit_columns` macro.**

In addition:

- A per-run audit table (`analytics_retail.metadata.dbt_run_log`) tracks every dbt invocation with start/end/status/row counts.
- Lineage is exposed via dbt's native `manifest.json` and a `lineage_edges` helper view for SQL access.
- A Power BI "Data Operations" dashboard (proprietary) visualizes the run log, lineage, and freshness SLAs.

---

## Rationale

The 8-column footer covers every distinct audit question we anticipate:

| Question | Column(s) used |
|---|---|
| "Where did this row come from?" | `_source_system`, `_source_record_id` |
| "When did this data leave the source?" | `_extracted_at` |
| "When did this row land in our warehouse?" | `_loaded_at` |
| "What's the source-to-warehouse lag?" | `_extracted_at` vs `_loaded_at` |
| "Which dbt run produced this?" | `_dbt_invocation_id` |
| "Which dbt model produced this?" | `_dbt_model` |
| "Has this row changed since I last saw it?" | `_record_hash` |
| "Is this row still active at source?" | `_is_deleted_at_source` |

Each column does work that no other column duplicates. The 8-column count is not arbitrary — it is the minimum that answers all the questions clients actually ask in production.

Implementing via a macro means model authors cannot forget to add audit columns. The macro is the single source of truth for audit behavior, making future changes (e.g., adding a new column) trivial — change the macro, rebuild the warehouse.

Storage cost is negligible. Snowflake compresses highly repetitive columns (`_source_system` = one of five values; `_dbt_model` = one of ~50 values) to near-zero overhead. The only column with high cardinality (`_record_hash`) costs roughly 1–2 GB compressed for a mid-market client's full warehouse — under $0.50/month in storage.

This pattern aligns with industry best practice. dbt's own documentation recommends a similar footer. Major analytics engineering blogs (dbt Labs, Datafold, Stemma) describe variations of this exact pattern as the standard.

---

## Consequences

**Easier:**

- Source traceability is one SQL query away
- Failed dbt runs can be precisely identified and rolled back
- Change detection between runs becomes a single `_record_hash` comparison
- Freshness monitoring is straightforward (`_loaded_at` comparisons)
- Enterprise governance reviews can be passed quickly

**Harder:**

- Model authors must include the macro call. Mitigated by linting in CI.
- Documentation must consistently mention that audit columns exist on every table. Mitigated by stating the convention once in Sections 4.2 and 4.18 and referencing it from each table.
- Row counts in `SELECT *` queries include audit columns. Mitigated by conventions: dashboards and reports never use `SELECT *`.

**New decisions this creates:**

- What is the retention policy for `dbt_run_log`? (Proposed: 12 months active, archived to long-term storage beyond. Decided in ADR when needed.)
- Should `_record_hash` be optional for very high-volume facts where compute cost is a concern? (Defer until measured.)
- Should the proprietary "Data Operations" dashboard be included in the standard pro license or sold separately? (Defer to pricing decision.)

---

## Related decisions

- ADR-001: Initial Tech Stack Selection (Snowflake's micro-partition handling makes columnar metadata cheap)
- ADR-003: Fuzzy Identity Resolution (uses `match_confidence` column, populated by the same macro pattern)
