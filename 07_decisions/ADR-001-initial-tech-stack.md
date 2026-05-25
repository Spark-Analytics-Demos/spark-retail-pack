# ADR-001: Initial Tech Stack Selection

**Status:** Accepted
**Date:** 2026-05-13
**Deciders:** Spark Analytics leadership

---

## Context

The Spark Retail Pack is being built as a productized data warehouse accelerator. Before any code can be written, the foundational tech stack must be chosen. These choices affect connector design, client onboarding, pricing, marketing, and the skills required of the implementation team. Changing them later is expensive.

Specifically, we need to decide on:
1. Cloud data warehouse
2. Transformation framework
3. Business intelligence / dashboarding tool
4. Semantic / metrics layer
5. Distribution model (open source vs. proprietary)

---

## Options considered

### 1. Cloud data warehouse

| Option | Pros | Cons |
|---|---|---|
| **Snowflake** | Mid-market pricing, dbt-native, strong cloning, multi-cloud | Slightly more expensive at the top end |
| BigQuery | Cheap at small scale, Google ecosystem | Less common in target market, GCP lock-in |
| Databricks | Best for ML-heavy use cases | Overkill for retail analytics, harder to sell |
| Redshift | AWS-native | Fading mindshare, slower innovation |

### 2. Transformation framework

| Option | Pros | Cons |
|---|---|---|
| **dbt Core** | Industry standard, open source, package-based distribution | Requires Git workflow comfort from clients |
| dbt Cloud | Managed orchestration | Pricing forces clients into dbt Labs' ecosystem |
| Matillion | Visual GUI | Proprietary, lock-in, less popular with engineers |
| Custom SQL pipelines | Maximum flexibility | Rebuilds what dbt already does well |

### 3. BI tool

| Option | Pros | Cons |
|---|---|---|
| **Power BI** | Wide adoption, often already in clients' M365 license, mid-market friendly | Less elegant than Looker; Microsoft ecosystem bias |
| Looker | Best semantic layer integration, enterprise polish | Expensive, requires LookML expertise |
| Metabase | Open source, easy demos | Less mature for enterprise sales |
| Tableau | Visual quality | Salesforce-owned now, pricing fragmenting |

### 4. Semantic layer

| Option | Pros | Cons |
|---|---|---|
| **dbt Semantic Layer (MetricFlow)** | Native to dbt, single ecosystem | Younger product, fewer integrations than alternatives |
| Cube | More mature, BI-tool agnostic | Adds a separate system to maintain |
| LookML | Powerful, deeply integrated with Looker | Tied to Looker |
| AtScale | Enterprise-grade | Heavyweight, expensive |

### 5. Distribution model

| Option | Pros | Cons |
|---|---|---|
| **Hybrid (open core + proprietary modules)** | Lead generation via OSS, upsell via pro, services revenue | Requires discipline on what's free vs. paid |
| Fully open source | Maximum adoption, community contributions | Hard to monetize, no differentiation from existing OSS packages |
| Fully proprietary | Cleanest revenue model | Slow adoption, "vendor lock-in" objection in sales |

---

## Decision

| Layer | Chosen |
|---|---|
| Cloud data warehouse | **Snowflake** |
| Transformation framework | **dbt Core** |
| BI tool | **Power BI** |
| Semantic layer | **dbt Semantic Layer (MetricFlow)** |
| Distribution model | **Hybrid (open core + proprietary modules + services)** |

---

## Rationale

**Snowflake** wins for the target market. Mid-market retail clients want managed, pay-per-use compute and don't want to administer infrastructure. Snowflake's cloning capability also makes demo environments cheap to spin up.

**dbt Core** is the de-facto standard. Distributing the pack as dbt packages means we get the entire dbt ecosystem (testing, documentation, lineage) for free, and clients can integrate the pack into their existing dbt project if they have one.

**Power BI** is chosen over Looker primarily because of distribution. Most mid-market clients already pay for Microsoft 365 with Power BI included. Looker has better technical fit but materially higher cost and skill requirements.

**dbt Semantic Layer** is the natural choice given we're already in the dbt ecosystem. It avoids running a second metrics system.

**Hybrid distribution** balances commercial reality with adoption needs. The open-source core is marketing and lead generation; the proprietary modules and services are revenue. This is the model dbt Labs, Airbyte, and Metabase have all used successfully.

---

## Consequences

**Easier:**

- Single warehouse and BI target simplifies testing, support, and documentation
- dbt's native testing and documentation reduce what we need to build ourselves
- Open-source core gives us a credible public artifact before any sale closes
- Power BI's prevalence in target market lowers sales friction

**Harder:**

- Snowflake-only means we will need a v2 multi-warehouse strategy when clients on BigQuery or Databricks ask
- Power BI dashboards are not portable to Looker or Tableau — building those is duplicate work for v2
- Maintaining two repos (open + pro) requires discipline about what crosses the boundary
- Need to be careful about Power BI version dependencies (Power BI Desktop vs. Service vs. Premium)

**New decisions this creates:**

- What exact dbt version do we pin to? (Decided per release; ADR-002 when made)
- What Power BI tier do we assume clients have? (Pro vs. Premium)
- How is the open-source repo licensed? (Likely MIT; ADR-003 when made)
- Where does the dbt Semantic Layer connection from Power BI run — dbt Cloud or self-hosted? (To be resolved before pro modules ship)
