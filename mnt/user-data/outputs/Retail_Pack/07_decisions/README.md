# Architecture Decision Records (ADRs)

This folder captures **why** we made the decisions we did, so future contributors don't have to re-litigate them.

An ADR is a short markdown file describing one decision: its context, the options considered, the choice made, and the consequences.

## Index

| # | Title | Status | Date |
|---|---|---|---|
| 001 | [Initial Tech Stack Selection](./ADR-001-initial-tech-stack.md) | Accepted | 2026-05-13 |
| 002 | [Audit and Lineage Architecture](./ADR-002-audit-and-lineage.md) | Accepted | 2026-05-13 |
| 003 | [Fuzzy Identity Resolution](./ADR-003-fuzzy-identity-resolution.md) | Accepted | 2026-05-13 |
| 004 | [dbt Core vs. dbt Cloud for Semantic Layer Access](./ADR-004-dbt-core-vs-cloud-semantic-layer.md) | Accepted | 2026-05-14 |

## Template

When adding new ADRs, follow this structure:

```markdown
# ADR-XXX: [Title]

**Status:** [Proposed | Accepted | Deprecated | Superseded by ADR-YYY]
**Date:** YYYY-MM-DD
**Deciders:** [Names]

## Context

What problem are we solving? What forces are at play?

## Options considered

1. Option A — pros, cons
2. Option B — pros, cons
3. Option C — pros, cons

## Decision

Which option was chosen and why.

## Consequences

What becomes easier? What becomes harder? What new decisions does this create?
```
