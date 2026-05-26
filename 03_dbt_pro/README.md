# spark_retail_pack_pro — Pro dbt Extension

The commercial-licensed Pro tier of the Spark Retail Pack. Extends the OSS core (`02_dbt_core/`) with the semantic layer, 11 advanced KPIs, AI-ready feature tables, and 6 Pro macros.

**License:** Commercial — see [LICENSE](./LICENSE). Not open-source.

---

## What's in the Pro tier

Per [Section 11](../01_design_docs/11_open_source_vs_pro_split.md) of the design document:

| Component | Description |
|---|---|
| `models/semantic/` | MetricFlow YAML definitions for all 25 KPIs — enables dbt Semantic Layer (ADR-004) |
| `models/advanced_metrics/` | 11 Pro KPIs: LTV cohort curves, blended CAC, predictive churn score, contribution margin, and more |
| `models/ai_ready/` | Feature-engineered tables for ML consumption (customer propensity, product affinity) |
| `macros/` | 6 Pro macros: `cohort_array`, `ltv_curve`, `weighted_roas`, `contribution_margin`, `churn_probability`, `ai_feature_vector` |

The OSS package (`02_dbt_core/`) must be set up first — this project depends on it via `packages.yml`.

---

## Status

**Phase 0 scaffolding complete.** Project structure and dependencies are in place. Semantic layer YAML and Pro model implementations are Phase 2 and Phase 3 work.

---

## Setup

This project assumes `02_dbt_core/` is installed and its virtual environment is active.

```bash
# From this directory
dbt deps   # installs OSS core as a local package dependency

dbt parse  # validates the Pro project parses correctly
```

The Pro project uses the same Snowflake credentials as the OSS project. Configure a `profiles.yml` here that mirrors the `spark_retail_pack` profile targets (or point `--profiles-dir` at `02_dbt_core/`).

---

## OSS / Pro boundary

**Never copy Pro models or macros into `02_dbt_core/`.** The boundary defined in Section 11 is the commercial differentiator. Violating it erodes the reason a client pays for Pro.

If something should be Pro per Section 11, it lives here. If it should be OSS, it lives in `02_dbt_core/`. When in doubt, check the design document before writing code.
