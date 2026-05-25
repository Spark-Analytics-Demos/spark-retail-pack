# Contributing to the Spark Retail Pack

Thank you for your interest in contributing to the Spark Retail Pack — an open-core data warehouse accelerator for retail and e-commerce.

This document covers how to contribute to the **open-source core** (`02_dbt_core/`). The proprietary modules (`03_dbt_pro/`, `04_dashboards/`) are not open to external contributions.

---

## Before you start

**This repository is in active early development.** v1 has not yet shipped. Some areas may be under heavy change; large contributions submitted before v1 release may need rework. Open an issue to discuss before starting substantial work.

If you're looking for context on the project's design, start with `01_design_docs/README.md`. The design document is the source of truth — contributions that conflict with it will be redirected.

---

## What contributions are welcome

Per Section 11.11 of the design document, the following contributions are accepted to the OSS core:

| Contribution type | Accepted? |
|---|---|
| Bug fixes in OSS models | ✅ Yes |
| Documentation improvements | ✅ Yes |
| New OSS macros (additive, non-breaking) | ✅ Yes |
| Tests and CI improvements | ✅ Yes |
| New connectors for v2 | ✅ Yes, with maintainer review |
| Refactoring of OSS models | ⚠️ Maintainer review required (avoid breaking changes) |
| Modifying the canonical model's column schema | ⚠️ Major version review; rare |
| Adding Pro features to OSS | ❌ No — erodes commercial differentiation |
| New modules outside the v1 roadmap | ❌ No — propose via issue first |

If you're unsure whether your contribution fits, open an issue with the proposal before writing code.

---

## Contributor License Agreement (CLA)

**All contributors must sign a CLA before their first pull request is merged.**

This is a standard practice for open-core projects. The CLA grants Spark Analytics the right to relicense the OSS code under the proprietary license when bundled into the Pro tier (per Section 11.12's versioning model). Your copyright stays with you; the CLA only grants license, not ownership.

The CLA is signed electronically via the [CLA Assistant](https://cla-assistant.io/) bot, which will comment on your first PR with a one-click signing link. Without a signed CLA, the PR cannot be merged.

If you're contributing on behalf of an employer, your employer may also need to sign a Corporate CLA. Check with your employer's open-source policy.

---

## How to contribute

### 1. Open an issue first

For anything beyond a typo fix, open a GitHub issue describing:

- The problem you're solving
- The approach you're proposing
- Which design section(s) the change relates to
- Whether you're planning to submit a PR yourself

A maintainer will respond with feedback, usually within one business week. Issues marked `good-first-issue` are intentionally scoped for new contributors.

### 2. Fork and branch

Fork the repository, then create a branch named for the change:

```
git checkout -b fix/staging-shopify-null-handling
git checkout -b feat/google-ads-connector
git checkout -b docs/clarify-pii-masking
```

Branch name prefixes follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat/` — new features
- `fix/` — bug fixes
- `docs/` — documentation only
- `refactor/` — code restructure with no functional change
- `test/` — adding or fixing tests
- `chore/` — build, CI, dependencies
- `perf/` — performance improvements

### 3. Follow the conventions

The design document defines the conventions. The most-checked ones during review:

- **Naming**: snake_case throughout; `stg_<source>__<table>`, `dim_<entity>`, `fact_<event>`, `int_<purpose>`
- **Audit columns**: Every core and mart model includes the 8-column footer via `add_audit_columns` macro (Section 4 Part 2 §4.31)
- **Tests**: `not_null` on PKs, `unique` on keys, `relationships` on FKs (Section 4 Part 3 §4.37)
- **Schema docs**: Every model has a `schema.yml` entry with description, columns, and `meta` (owner, classification, pii_present)
- **PII handling**: Every PII column uses the `pii_mask` macro (Section 8.5)
- **No Pro logic**: OSS contributions cannot introduce features documented as Pro tier (Section 11)

### 4. Test locally before opening a PR

Run the full test suite locally:

```bash
cd 02_dbt_core
dbt deps
dbt build --select state:modified+
dbt test
```

If your change touches the demo data:

```bash
cd 05_demo_data
python -m pytest tests/
```

PRs that fail CI may not be reviewed until they pass.

### 5. Write a clear PR description

The PR template will prompt for:

- **Summary**: What does this change do?
- **Related issue**: Closes #N
- **Design section**: Which section of `01_design_docs/` this implements or modifies
- **Testing**: How you tested it
- **Breaking changes**: Any? (If yes, this is almost certainly a discussion before code)
- **Checklist**:
  - [ ] CLA signed
  - [ ] Tests added/updated
  - [ ] Documentation updated
  - [ ] No Pro features added to OSS
  - [ ] Audit columns present on new core/mart models

### 6. Review process

A maintainer will review within one business week. Reviews focus on:

- Correctness against the design document
- Naming, conventions, and code style
- Test coverage
- Performance implications (especially for high-volume models)
- Open-core boundary preservation

Expect at least one round of feedback for non-trivial PRs. Reviewers are friendly but rigorous — the goal is product quality, not gatekeeping.

---

## Code style

### SQL (dbt models)

- Use lowercase for SQL keywords (`select`, not `SELECT`) — modern dbt convention
- Trailing commas in CTEs and select lists
- One column per line in long select statements
- CTEs named in `snake_case`, each with a comment explaining its purpose
- Jinja indented for readability inside dbt models

Example:

```sql
{{ config(
    materialized='incremental',
    unique_key='order_id',
    on_schema_change='append_new_columns'
) }}

with source_orders as (
    -- Raw Shopify orders from the bronze layer
    select * from {{ source('shopify', 'orders') }}
    {% if is_incremental() %}
      where updated_at >= {{ incremental_lookback() }}
    {% endif %}
),

renamed as (
    select
        id as order_id,
        customer_id,
        created_at,
        total_price,
        currency
    from source_orders
)

select * from renamed
```

### YAML (schema, sources, semantic models)

- 2-space indentation
- Use `>` or `|` for multi-line descriptions
- Always include `meta` block with `owner`, `domain`, and `pii_present` on every model

### Python (demo data generator)

- Python 3.11+
- Type hints required on public functions
- Follow PEP 8; we use `ruff` for linting and `black` for formatting
- Tests with `pytest`; aim for >80% coverage on the generator code

### Markdown (documentation)

- One sentence per line in long-form docs (helps with diffs)
- Use ATX-style headers (`#`, `##`, `###`)
- Fenced code blocks with language specified
- Tables for structured content; lists for sequence

---

## Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>

<body explaining what and why, not how>

<footer with breaking changes, issue refs>
```

Examples:

```
feat(staging): add stg_shopify__refunds

Implements the refunds staging model per Section 6.4.
Includes line-level refund tracking and chargeback flag.

Closes #42
```

```
fix(dim_customer): handle null phone numbers in E.164 normalize

Previously the phone_hash column was NULL when source phone was empty,
causing identity resolution Tier 2 to fail. Now returns NULL hash
explicitly and identity resolution falls through to Tier 3.

Refs Section 4 Part 1 §4.3, ADR-003
```

---

## Where to get help

- **GitHub Discussions**: For design questions, feature ideas, and general discussion
- **GitHub Issues**: For bug reports and specific change proposals
- **Discord** (link in main README): For real-time chat with other contributors
- **Maintainers**: Tag `@spark-analytics/maintainers` in PRs and issues

For commercial questions (Pro tier, services, custom development), email [contact email TBD] — these are not handled in the open-source channels.

---

## Code of conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you agree to uphold this code. Report unacceptable behavior to [maintainer email TBD].

---

## License

By contributing, you agree that your contributions will be licensed under the MIT License (the same license as the OSS core), and that Spark Analytics may relicense the contributions as part of the Pro tier under the terms of the CLA.

---

## Thank you

Open-source contributions are what make products like this sustainable. Every fix, doc improvement, and connector adds real value. We appreciate the time you're putting in.
