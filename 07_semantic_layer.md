# Section 7: Semantic Layer

> **Document status:** Draft v1
> **Audience:** Engineering team, BI developers, AI/ML engineers building on top of the warehouse, analytics consumers
> **Purpose:** Define how the canonical data model (Section 4) and KPI catalog (Section 5) are encoded into a queryable semantic layer using dbt Semantic Layer (MetricFlow). Also defines the business glossary that documents every term in plain language and the entity ontology that supports AI-ready querying.

---

## 7.1 What this section defines

The semantic layer is the boundary between the warehouse and its consumers (Power BI, AI assistants, embedded analytics, ad-hoc queries). It exposes:

1. **Metrics** — every KPI in the catalog, encoded as a MetricFlow definition
2. **Entities** — the canonical business objects (customer, order, product) and their relationships
3. **Dimensions** — what metrics can be sliced by
4. **A business glossary** — every term in plain language for non-technical consumers
5. **An entity ontology** — machine-readable relationships used for AI-driven querying

This section specifies **what** the semantic layer contains, not how MetricFlow itself works (that's covered by dbt's documentation). It establishes the project structure, naming conventions, and design patterns the pack uses.

---

## 7.2 Why a semantic layer

Without a semantic layer, every consumer of the warehouse computes metrics independently:

- Power BI computes "active customers" with its own DAX formula
- The AI assistant computes it with its own SQL
- Ad-hoc analysts compute it with whatever they remember
- Three different numbers, three different stakeholders, three different meetings about which is correct

The semantic layer solves this by being the **only place a metric formula exists**. Every consumer queries the same definition. The cost is one extra layer to maintain; the benefit is metric consistency across the entire organization.

For the Spark Retail Pack specifically, the semantic layer also enables three product capabilities that are otherwise impractical:

1. **AI-ready querying** — an LLM can answer "what was active customers in March?" because the definition of "active customers" is encoded once and machine-readable
2. **BI-tool portability** — when a client switches from Power BI to Looker, only the BI templates change; the metric definitions don't
3. **Embedded analytics** — third-party tools embed dashboards by calling the semantic layer's API, never raw SQL

---

## 7.3 Tool choice — dbt Semantic Layer (MetricFlow)

ADR-001 established dbt Semantic Layer as the metrics tool. The rationale was: it lives natively in the dbt ecosystem, avoiding a second metrics system to maintain. This section operationalizes that choice.

### What dbt Semantic Layer provides

- **YAML-based metric definitions** that live alongside dbt models
- **A query engine** (MetricFlow) that compiles metric queries into SQL at runtime
- **A GraphQL API** that BI tools and AI assistants call
- **Native dbt lineage** — metric definitions show up in the lineage graph alongside models
- **Caching** for query performance

### What dbt Semantic Layer does NOT provide

- A UI for non-technical metric authoring (clients can use Lightdash, Cube Cloud, or similar layered on top — out of v1 scope)
- Real-time / streaming metrics (batch only in v1)
- Full natural-language query parsing (that's a Spark AI assistant feature, built on top)

### Version pinning

Per Section 4 Part 3 Section 4.48, the pack pins:

```yaml
# packages.yml
- package: dbt-labs/metrics
  version: 1.7.5
```

MetricFlow 1.7 supports all features the pack uses; clients upgrading to MetricFlow 2.x will need a migration step (planned for pack v2.0).

---

## 7.4 Semantic layer project structure

The semantic layer lives within the proprietary dbt project (`spark_retail_pack_pro`), not the open-source core. This decision aligns with the open/pro split (Section 4 Part 3, Section 4.45 and the upcoming Section 11): basic KPI SQL is open source; the encoded semantic definitions and the AI-ready metadata that surround them are proprietary.

```
spark_retail_pack_pro/
└── models/
    └── semantic/
        ├── _semantic__sales.yml         # Sales Analytics module
        ├── _semantic__customer.yml      # Customer 360 module
        ├── _semantic__inventory.yml     # Inventory Health module
        ├── _semantic__shared.yml        # Entities and dimensions shared across modules
        ├── _semantic__glossary.yml      # Business glossary
        ├── _semantic__ontology.yml      # Entity-relationship ontology
        └── ai_metadata/
            ├── metric_synonyms.yml      # Synonyms for natural language matching
            ├── metric_examples.yml      # Example questions per metric
            └── domain_knowledge.yml     # Domain-specific knowledge for the AI layer
```

The files are organized by **business domain** (sales, customer, inventory) rather than by MetricFlow object type. This makes it easier for a non-technical owner of "all Customer 360 metrics" to find their definitions in one place.

---

## 7.5 The four MetricFlow primitives

MetricFlow defines four kinds of objects. The pack uses all four.

### Semantic models

A **semantic model** wraps a dbt model and declares its grain, entities (joinable IDs), measures (numeric columns aggregatable), and dimensions (sliceable attributes).

Every fact and dimension in the pack has one corresponding semantic model. They live in the module YAML files.

### Entities

An **entity** is a business object that can be joined across semantic models — customer, order, product. Entities have an ID column that resolves the join.

### Measures

A **measure** is a numeric column with an aggregation function (sum, count, average, min, max). Measures are the raw ingredients of metrics.

### Metrics

A **metric** is the consumer-facing object. It defines a calculation on one or more measures, with allowed aggregations across time and dimensions.

MetricFlow supports four metric types, all of which the pack uses:

| Type | Pack examples | Notes |
|---|---|---|
| `simple` | `gmv`, `order_count`, `total_inventory_value` | One measure, one aggregation |
| `ratio` | `aov`, `refund_rate`, `repeat_purchase_rate`, `roas_by_channel` | Numerator / denominator |
| `derived` | `revenue_growth_pct`, `lifetime_value` | Computed from other metrics |
| `cumulative` | (none in v1) | Running totals — deferred to v2 |

---

## 7.6 Example: Sales Analytics semantic models

Concrete YAML for the Sales Analytics module. This is what the file `_semantic__sales.yml` looks like in v1.

### Semantic model for `fact_orders`

```yaml
version: 2

semantic_models:
  - name: orders
    description: |
      Order header grain. One row per order. Source of truth for order-level
      revenue, status, and payment information. See Section 4 Part 2 Section
      4.19 for the underlying fact table specification.
    model: ref('fact_orders')
    
    defaults:
      agg_time_dimension: order_date

    # Entities — joinable IDs
    entities:
      - name: order
        type: primary
        expr: order_id
      - name: customer
        type: foreign
        expr: customer_id
      - name: channel
        type: foreign
        expr: channel_sk
      - name: geography
        type: foreign
        expr: geography_sk
      - name: payment_method
        type: foreign
        expr: payment_method_sk

    # Measures — raw aggregatable columns
    measures:
      - name: gross_amount
        description: Order value before discounts and refunds.
        agg: sum
        expr: gross_amount
      - name: discount_amount
        description: Total discounts applied at order level.
        agg: sum
        expr: discount_amount
      - name: refunded_amount
        description: Total refunded against this order over time.
        agg: sum
        expr: refunded_amount
      - name: tax_amount
        description: Total tax collected on this order.
        agg: sum
        expr: tax_amount
      - name: shipping_amount
        description: Total shipping charges on this order.
        agg: sum
        expr: shipping_amount
      - name: order_count
        description: Count of distinct orders.
        agg: count_distinct
        expr: order_id

    # Dimensions — sliceable attributes
    dimensions:
      - name: order_date
        type: time
        type_params:
          time_granularity: day
        expr: order_date
      - name: order_status
        type: categorical
        expr: order_status
      - name: financial_status
        type: categorical
        expr: financial_status
      - name: is_first_order
        type: categorical
        expr: is_first_order
      - name: is_repeat_order
        type: categorical
        expr: is_repeat_order
```

> **Note on the cancelled-order filter.** Every Sales Analytics metric in Section 5 explicitly excludes cancelled orders. In MetricFlow this is implemented as a `filter` block on each metric (not a single semantic-model-level filter, which is not a MetricFlow concept). The pattern below applies `filter: "{{ Dimension('order__order_status') }} != 'cancelled'"` to every Sales metric. For brevity, the filter is omitted from individual metric examples below — assume it's present.

### Metrics defined on top of `orders`

```yaml
metrics:
  # KPI 1 — Gross Merchandise Value
  - name: gmv
    label: "Gross Merchandise Value"
    description: |
      Total order value before refunds. Excludes cancelled orders.
      Discounts ARE deducted (the formula uses gross_amount which is post-discount).
      Tax and shipping are excluded. See Section 5.4 KPI 1.
    type: simple
    type_params:
      measure: gross_amount
    meta:
      owner: finance
      module: sales_analytics
      tier: oss
      kpi_id: sales.gmv
      catalog_section: "5.4 KPI 1"

  # KPI 2 — Net Revenue
  - name: net_revenue
    label: "Net Revenue"
    description: |
      Revenue retained by the business after discounts and refunds.
      Excludes tax (a liability) and shipping (pass-through). 
      The metric reported to investors. See Section 5.4 KPI 2.
    type: derived
    type_params:
      expr: gross_amount - discount_amount - refunded_amount
      metrics:
        - name: gross_amount
        - name: discount_amount
        - name: refunded_amount
    meta:
      owner: finance
      module: sales_analytics
      tier: oss
      kpi_id: sales.net_revenue
      catalog_section: "5.4 KPI 2"

  # KPI 3 — Order Count
  - name: order_count
    label: "Order Count"
    description: Total number of completed orders. Excludes cancelled. See Section 5.4 KPI 3.
    type: simple
    type_params:
      measure: order_count
    meta:
      owner: operations
      module: sales_analytics
      tier: oss
      kpi_id: sales.order_count

  # KPI 4 — Average Order Value
  - name: average_order_value
    label: "Average Order Value (AOV)"
    description: |
      Net revenue divided by order count. Slicing this by any dimension correctly
      recomputes AOV for that slice — do not average individual order amounts.
      See Section 5.4 KPI 4.
    type: ratio
    type_params:
      numerator: net_revenue
      denominator: order_count
    meta:
      owner: marketing
      module: sales_analytics
      tier: oss
      kpi_id: sales.average_order_value

  # KPI 5 — Revenue Growth %
  - name: revenue_growth_pct
    label: "Revenue Growth %"
    description: |
      Period-over-period revenue change as a percentage. Returns NULL when prior
      period revenue is zero. See Section 5.4 KPI 5.
    type: derived
    type_params:
      expr: |
        CASE
          WHEN net_revenue_prior IS NULL OR net_revenue_prior = 0 THEN NULL
          ELSE (net_revenue - net_revenue_prior) / net_revenue_prior * 100
        END
      metrics:
        - name: net_revenue
        - name: net_revenue
          alias: net_revenue_prior
          offset_window: 1 month
    meta:
      owner: finance
      module: sales_analytics
      tier: oss
      kpi_id: sales.revenue_growth_pct
      grain_exclusions: [daily]   # too noisy for daily; semantic layer enforces

  # KPI 9 — Tax Collected
  - name: tax_collected
    label: "Tax Collected"
    description: |
      Total tax across orders. Almost always sliced by geography for tax filing.
      Refunded tax is NOT subtracted here — for net tax filing, compute separately.
      See Section 5.4 KPI 9.
    type: simple
    type_params:
      measure: tax_amount
    meta:
      owner: finance
      module: sales_analytics
      tier: oss
      kpi_id: sales.tax_collected
```

### Pro-tier metrics on `orders` + `refunds`

```yaml
# KPI 6 — Refund Rate (Pro)
  - name: refund_rate
    label: "Refund Rate"
    description: |
      Percentage of revenue refunded. Match window is by refund_date,
      not order_date — refunds in March against February orders are
      attributed to March. See Section 5.4 KPI 6.
    type: ratio
    type_params:
      numerator:
        name: refunded_amount_period
        filter: "{{ Dimension('refund__refund_date') }} between {{ period_start }} and {{ period_end }}"
      denominator:
        name: gross_amount
    meta:
      owner: operations
      module: sales_analytics
      tier: pro
      kpi_id: sales.refund_rate
      grain_exclusions: [daily]

  # KPI 8 — Revenue by Channel (Pro)
  - name: revenue_by_channel
    label: "Revenue by Channel"
    description: |
      Net revenue grouped by channel. Uses the proprietary channel hierarchy
      (online → marketplace → social → search). See Section 5.4 KPI 8.
    type: simple
    type_params:
      measure: net_revenue
    group_by:
      - Entity('channel')
    meta:
      owner: marketing
      module: sales_analytics
      tier: pro
      kpi_id: sales.revenue_by_channel
```

This is the **pattern**. The full Sales Analytics YAML defines 9 metrics (KPIs 1–9), each tagged with its kpi_id, owner, module, tier, and catalog section so traceability back to Section 5 is automatic.

---

## 7.7 Customer 360 semantic models

The Customer 360 module is the most complex because it joins across 5 facts. The pattern stays the same — declare semantic models, declare measures, declare metrics. Sketched below.

> **Note on completeness:** The YAML excerpts in Sections 7.7 and 7.8 are **illustrative**, not exhaustive. They reference supporting measures and metrics (e.g., `repeat_customer_count`, `customers_who_purchased`, `marketing_spend`, `new_customers_attributed`) that exist in the full module YAML but are not shown here in the interest of readability. The complete YAML files ship in `spark_retail_pack_pro/models/semantic/` and are also exported in the design appendix.

### Semantic model for `fact_customer_state_daily`

```yaml
semantic_models:
  - name: customer_state
    description: |
      Daily snapshot of each customer's state. Foundation of Customer 360
      retention and activity analytics. See Section 4 Part 2 Section 4.25.
    model: ref('fact_customer_state_daily')

    defaults:
      agg_time_dimension: snapshot_date

    entities:
      - name: customer
        type: primary
        expr: customer_id
      - name: customer_state
        type: natural
        expr: customer_state_sk

    measures:
      - name: lifetime_revenue
        description: Cumulative net revenue per customer to date.
        agg: sum
        expr: lifetime_revenue
      - name: customer_count_active_30d
        description: Count of customers active in trailing 30 days.
        agg: count_distinct
        expr: |
          CASE WHEN is_active_30d THEN customer_id END
      - name: customer_count_active_90d
        description: Count of customers active in trailing 90 days.
        agg: count_distinct
        expr: |
          CASE WHEN is_active_90d THEN customer_id END
      - name: customer_count_total
        description: Total customers in snapshot.
        agg: count_distinct
        expr: customer_id

    dimensions:
      - name: snapshot_date
        type: time
        type_params:
          time_granularity: day
      - name: customer_segment
        type: categorical
      - name: is_active_30d
        type: categorical
      - name: is_active_90d
        type: categorical
      - name: is_repeat_customer
        type: categorical
```

### Key Customer 360 metrics

```yaml
metrics:
  # KPI 10 — Active Customers (30-day)
  - name: active_customers_30d
    label: "Active Customers (30-day)"
    description: |
      Distinct customers with at least one completed order in trailing 30 days,
      as of the latest snapshot date in the period. NON-ADDITIVE across time.
      See Section 5.5 KPI 10.
    type: simple
    type_params:
      measure: customer_count_active_30d
    meta:
      owner: growth
      module: customer_360
      tier: oss
      kpi_id: customer.active_customers_30d
      additivity: non_additive
      non_additive_dimension:
        name: snapshot_date
        window_choice: max
        window_groupings: [customer_id]

  # KPI 14 — Repeat Purchase Rate
  - name: repeat_purchase_rate
    label: "Repeat Purchase Rate"
    description: |
      Ratio of repeat customers to all customers who purchased in the period.
      See Section 5.5 KPI 14.
    type: ratio
    type_params:
      numerator: repeat_customer_count
      denominator: customers_who_purchased
    meta:
      owner: growth
      module: customer_360
      tier: oss
      kpi_id: customer.repeat_purchase_rate

  # KPI 17 — Customer Acquisition Cost by Channel (Pro)
  - name: cac_by_channel
    label: "Customer Acquisition Cost by Channel"
    description: |
      Marketing spend divided by attributed new customers, per channel.
      Uses last-touch attribution in v1. See Section 5.5 KPI 17.
    type: ratio
    type_params:
      numerator: marketing_spend
      denominator: new_customers_attributed
    group_by:
      - Entity('channel')
    meta:
      owner: marketing
      module: customer_360
      tier: pro
      kpi_id: customer.cac_by_channel
      attribution_method: last_touch
```

The `non_additive_dimension` block on active customers is what tells MetricFlow not to sum these across time — exactly the protection mentioned in Section 5.7. Power BI, the AI assistant, and ad-hoc SQL all respect this automatically.

---

## 7.8 Inventory Health semantic models

Inventory metrics are heavily point-in-time, which the semantic layer represents via snapshot-aware non-additive measures.

```yaml
semantic_models:
  - name: inventory_snapshot
    description: |
      Daily snapshot of SKU stock position by location. See Section 4 Part 2 
      Section 4.26.
    model: ref('fact_inventory_snapshot')

    defaults:
      agg_time_dimension: snapshot_date

    entities:
      - name: product
        type: foreign
        expr: product_sk
      - name: location
        type: foreign
        expr: location_sk
      - name: inventory_snapshot
        type: natural
        expr: inventory_snapshot_sk

    measures:
      - name: inventory_value
        description: Cost-basis value of inventory.
        agg: sum
        expr: inventory_value
      - name: quantity_on_hand
        agg: sum
        expr: quantity_on_hand
      - name: quantity_available
        agg: sum
        expr: quantity_available
      - name: sku_count
        description: Count of distinct SKUs in snapshot.
        agg: count_distinct
        expr: sku
      - name: sku_count_out_of_stock
        agg: count_distinct
        expr: |
          CASE WHEN is_out_of_stock THEN sku END
      - name: sku_count_slow_moving
        agg: count_distinct
        expr: |
          CASE WHEN is_slow_mover THEN sku END

    dimensions:
      - name: snapshot_date
        type: time
        type_params:
          time_granularity: day
      - name: is_out_of_stock
        type: categorical
      - name: is_slow_mover
        type: categorical

metrics:
  - name: total_inventory_value
    label: "Total Inventory Value"
    description: Cost-basis inventory value at end-of-period snapshot.
    type: simple
    type_params:
      measure: inventory_value
    meta:
      owner: operations
      module: inventory_health
      tier: oss
      kpi_id: inventory.total_inventory_value
      additivity: non_additive
      non_additive_dimension:
        name: snapshot_date
        window_choice: max

  - name: stockout_rate
    label: "Stockout Rate"
    description: |
      Percentage of SKUs at zero stock. End-of-day variant. 
      See Section 5.6 KPI 23.
    type: ratio
    type_params:
      numerator: sku_count_out_of_stock
      denominator: sku_count
    meta:
      owner: operations
      module: inventory_health
      tier: oss
      kpi_id: inventory.stockout_rate
```

---

## 7.9 Shared semantic objects

Some entities and dimensions are shared across all three modules. These live in `_semantic__shared.yml`.

```yaml
version: 2

semantic_models:
  # Customer dimension — joined by Sales, Customer 360
  - name: customer_dim
    model: ref('dim_customer')
    entities:
      - name: customer
        type: primary
        expr: customer_id
    dimensions:
      - name: customer_segment
        type: categorical
      - name: customer_status
        type: categorical
      - name: acquisition_channel
        type: categorical
      - name: country_code
        type: categorical
      - name: is_b2b_customer
        type: categorical
      - name: first_order_date
        type: time
        type_params:
          time_granularity: day

  # Product dimension — joined by Sales, Inventory
  - name: product_dim
    model: ref('dim_product')
    entities:
      - name: product
        type: primary
        expr: product_sk
      - name: sku
        type: natural
        expr: sku
    dimensions:
      - name: category
        type: categorical
      - name: subcategory
        type: categorical
      - name: brand
        type: categorical
      - name: vendor
        type: categorical
      - name: is_active
        type: categorical

  # Date — used everywhere
  - name: date
    model: ref('dim_date')
    entities:
      - name: date
        type: primary
        expr: date_sk
    dimensions:
      - name: date_actual
        type: time
        type_params:
          time_granularity: day
      - name: day_name
        type: categorical
      - name: month_name
        type: categorical
      - name: fiscal_year
        type: categorical
      - name: is_holiday
        type: categorical
      - name: is_weekend
        type: categorical
```

By centralizing these, a change to (say) the customer segment definition propagates to every metric that slices by segment. This is the core promise of a semantic layer.

---

## 7.10 Naming conventions

Naming discipline in the semantic layer matters more than in regular code, because metric names are user-facing — they appear in dashboard headers, AI chat responses, and consumer queries.

| Object type | Convention | Examples |
|---|---|---|
| **Metric name** | snake_case, business-readable | `net_revenue`, `cac_by_channel`, `repeat_purchase_rate` |
| **Metric label** | Title Case, what shows in dashboards | "Net Revenue", "Customer Acquisition Cost by Channel" |
| **Measure name** | snake_case, technical | `gross_amount`, `customer_count_active_30d` |
| **Entity name** | singular noun | `customer` not `customers`, `order` not `orders` |
| **Dimension name** | snake_case, matches source column where possible | `customer_segment`, `order_status` |
| **kpi_id (meta)** | dot-separated module.id | `sales.gmv`, `customer.lifetime_value` |

### Why labels matter

When the AI assistant says "Net Revenue was $1.2M last month," it pulls "Net Revenue" from the label field. When Power BI displays a metric in a chart title, it pulls the label. When a user types "show me net rev" into the AI, the synonym mapping resolves to the metric named `net_revenue`. All three depend on the label being correct.

The pack enforces in CI that every metric has both a `name` (snake_case) and a `label` (display text).

---

## 7.11 The business glossary

Beyond MetricFlow definitions, the pack ships a separate business glossary in `_semantic__glossary.yml`. The glossary defines every business term in plain language, with domain ownership.

### Glossary structure

```yaml
version: 2

glossary:
  - term: "Active Customer"
    definition: |
      A customer with at least one completed order in the trailing 30 days
      (90-day variant is "Active Customer (90-day)"). Cancelled and refunded
      orders still count toward this — only orders that never completed are
      excluded.
    domain: customer
    owner: growth_team
    related_metrics:
      - active_customers_30d
      - active_customers_90d
    synonyms:
      - "engaged customer"
      - "recent buyer"
    technical_definition: |
      EXISTS (
        SELECT 1 FROM fact_orders 
        WHERE customer_id = THIS_CUSTOMER 
          AND order_date >= CURRENT_DATE - INTERVAL '30 days'
          AND order_status NOT IN ('cancelled')
      )

  - term: "Average Order Value"
    abbreviation: "AOV"
    definition: |
      Net revenue divided by completed order count for the period.
      A common error is averaging individual order amounts — that produces
      a different (typically lower) number. The pack always computes AOV
      as total / count, which is correct for slicing.
    domain: sales
    owner: finance_team
    related_metrics:
      - average_order_value
    synonyms:
      - "AOV"
      - "mean order value"

  - term: "Customer Acquisition Cost"
    abbreviation: "CAC"
    definition: |
      Marketing spend divided by new customers attributed to a channel.
      "New customer" means first-ever completed purchase. v1 uses last-touch 
      attribution; multi-touch is a v2 feature. CAC for organic channels
      defaults to zero (no spend).
    domain: marketing
    owner: marketing_team
    related_metrics:
      - cac_by_channel
    synonyms:
      - "CAC"
      - "cost per acquisition"
      - "CPA"

  - term: "Days of Supply"
    definition: |
      Available inventory for an SKU divided by the trailing 28-day average
      daily sales rate. Indicates how many days the current stock will last
      at recent demand levels. NULL when there are no sales in 28 days.
    domain: inventory
    owner: operations_team
    related_metrics:
      - days_of_supply
    synonyms:
      - "DOS"
      - "stock days"
      - "weeks of supply" (when shown as DOS / 7)

  - term: "Repeat Customer"
    definition: |
      A customer who has placed at least 2 completed orders, where the second
      order is within the period being analyzed. Excludes refunded-only orders.
    domain: customer
    owner: growth_team
    related_metrics:
      - repeat_customer_count
      - repeat_purchase_rate

  - term: "Sell-Through Rate"
    definition: |
      For a cohort of SKUs received on a specific date, the percentage of units
      sold within a fixed window (typically 30, 60, or 90 days from receipt).
      Pack default is 60 days. Apparel typically uses 30; durable goods 90.
    domain: inventory
    owner: merchandising_team
    related_metrics:
      - sell_through_rate

  # ... continues for every term referenced in the KPI catalog
```

### Why the glossary is separate from metrics

A metric definition is technical — it tells MetricFlow how to compute. A glossary entry is consumer-facing — it tells a marketing manager what "Active Customer" means without requiring them to read SQL.

Some terms appear in the glossary but are not metrics (e.g., "Cohort," "B2B Customer," "Reporting Currency"). Some metrics map to multiple glossary terms (CAC has both "Customer Acquisition Cost" and "CAC" as entries pointing at the same metric).

The glossary is consumed by:

- The AI assistant (synonyms field maps "engaged customer" → `active_customers_30d`)
- The Power BI tooltip layer (definitions appear on hover)
- A standalone glossary view in dashboards
- The dbt docs site

### Glossary maintenance

Every metric added in `metrics:` blocks must have a corresponding glossary term, enforced by a CI check. The check parses both files and flags metrics without a glossary entry.

---

## 7.12 The entity ontology

The entity ontology is a machine-readable representation of how the pack's business objects relate. It's separate from MetricFlow's `entities` (which define joins between semantic models). The ontology answers a different question: **"What does this concept mean in this business, and what is it connected to?"**

### Ontology structure

```yaml
version: 2

ontology:
  entities:
    - name: Customer
      description: |
        A person or business that has interacted with the company through
        any source system. Identity-resolved across Shopify, Stripe, and Klaviyo.
      identifier: customer_id
      type: party
      attributes:
        - name: email
        - name: country
        - name: segment
        - name: lifetime_value
      relationships:
        - predicate: places
          target: Order
          cardinality: one_to_many
        - predicate: receives
          target: EmailEngagement
          cardinality: one_to_many
        - predicate: belongs_to
          target: Segment
          cardinality: many_to_one
        - predicate: acquired_via
          target: MarketingCampaign
          cardinality: many_to_one
        - predicate: located_in
          target: Geography
          cardinality: many_to_one

    - name: Order
      description: |
        A completed or pending purchase transaction. Excludes cancelled orders
        in most analytical contexts. Source of truth is Shopify.
      identifier: order_id
      type: transaction
      attributes:
        - name: order_date
        - name: net_amount
        - name: order_status
      relationships:
        - predicate: placed_by
          target: Customer
          cardinality: many_to_one
        - predicate: contains
          target: OrderLine
          cardinality: one_to_many
        - predicate: paid_with
          target: PaymentMethod
          cardinality: many_to_one
        - predicate: refunded_by
          target: Refund
          cardinality: one_to_many

    - name: Product
      description: |
        A SKU (stock keeping unit). One row per variant. Identity is the SKU
        from Shopify.
      identifier: sku
      type: physical_object
      attributes:
        - name: category
        - name: brand
        - name: unit_price
      relationships:
        - predicate: ordered_in
          target: OrderLine
          cardinality: one_to_many
        - predicate: stocked_at
          target: WarehouseLocation
          cardinality: many_to_many

    - name: MarketingCampaign
      description: A paid marketing campaign. Source is Meta Ads in v1.
      identifier: campaign_id
      type: event_series
      relationships:
        - predicate: acquired
          target: Customer
          cardinality: one_to_many
        - predicate: spent_via
          target: Channel
          cardinality: many_to_one

    # ... continues for Refund, EmailEngagement, Session, InventorySnapshot, etc.

  predicates:
    - name: places
      inverse: placed_by
      description: A customer places an order.
    - name: contains
      inverse: contained_in
      description: An order contains line items.
    - name: paid_with
      inverse: used_in
      description: An order is paid with a payment method.

  domains:
    - name: sales
      entities: [Order, OrderLine, Refund, PaymentMethod]
    - name: customer
      entities: [Customer, Segment, EmailEngagement, Session, MarketingCampaign]
    - name: inventory
      entities: [Product, InventorySnapshot, InventoryMovement, WarehouseLocation]
    - name: shared
      entities: [Geography, Channel, Date]
```

### Why the ontology matters

The ontology powers three capabilities:

1. **AI-driven query construction.** When a user asks "show me customers who bought from a campaign last week," the LLM uses the ontology to construct a valid query: `Customer → places → Order` AND `Customer → acquired_via → MarketingCampaign`. Without the ontology, the LLM would have to infer relationships from SQL.

2. **Schema understanding.** New analysts (and new AI integrations) can read the ontology to understand the business without reading every SQL model.

3. **Future knowledge-graph capabilities.** The ontology is the foundation for a v2 knowledge graph that supports inference ("a customer with multiple high-value orders is a candidate VIP segment member").

The ontology is intentionally **simpler than a full OWL/RDF schema**. The pack uses YAML for human readability rather than RDF for formal reasoning. If clients need RDF, a converter macro is in the pro extensions.

---

## 7.13 AI metadata for natural-language querying

Beyond the formal ontology, the pack ships AI-specific metadata that makes natural-language querying robust. This lives in `ai_metadata/` and is consumed by the Spark AI assistant feature (which sits on top of the semantic layer).

### Metric synonyms

```yaml
# ai_metadata/metric_synonyms.yml
synonyms:
  - metric: net_revenue
    terms:
      - "net rev"
      - "net sales"
      - "revenue after refunds"
      - "real revenue"
      - "what we kept"

  - metric: gmv
    terms:
      - "gross merchandise value"
      - "total sales"
      - "gross sales"
      - "topline"

  - metric: average_order_value
    terms:
      - "AOV"
      - "average basket"
      - "average cart value"
      - "average sale"

  - metric: cac_by_channel
    terms:
      - "CAC"
      - "acquisition cost"
      - "cost per customer"
      - "what we pay per new customer"

  - metric: lifetime_value
    terms:
      - "LTV"
      - "customer lifetime value"
      - "CLV"
      - "value per customer"
```

When the AI sees "What's our CAC for Facebook?", the synonym mapping resolves "CAC" → `cac_by_channel` and "Facebook" → channel = `paid_social_meta`. The query is now well-formed.

### Metric examples

```yaml
# ai_metadata/metric_examples.yml
examples:
  - metric: net_revenue
    example_questions:
      - "What was our revenue last month?"
      - "How much money did we make in Q1?"
      - "Show me revenue by channel for January"
      - "Is revenue up or down year over year?"
    example_dimensions:
      - channel
      - geography
      - customer_segment
    example_grains:
      - month
      - quarter
      - year

  - metric: active_customers_30d
    example_questions:
      - "How many active customers do we have?"
      - "Active customers this month"
      - "Active customers by segment"
    caveats: |
      This is a point-in-time measure — never sum across days. If the user asks
      for "total active customers over the year" the AI should clarify they
      likely want unique customers, which is a different metric.
```

The AI assistant uses these examples to:

- Understand the variety of questions a metric can answer
- Choose default dimensions for ambiguous queries
- Flag known pitfalls (the `caveats` field)

### Domain knowledge

```yaml
# ai_metadata/domain_knowledge.yml
domain_facts:
  - fact: "Black Friday is typically the highest-revenue day of the year for D2C retail"
    relevance: high
    used_for: anomaly_explanation
  
  - fact: "Apple Mail Privacy Protection (introduced 2021) inflates email open rates by approximately 30-50%"
    relevance: medium
    used_for: metric_caveat
    affects_metrics: [email_engagement_rate]
  
  - fact: "Meta's platform-reported conversions are typically 2-4x higher than warehouse-attributed conversions due to 7-day attribution windows"
    relevance: high
    used_for: metric_caveat
    affects_metrics: [roas_by_channel]

  - fact: "Inventory turnover benchmark for D2C retail is 4-8 turns per year"
    relevance: medium
    used_for: contextualization
    affects_metrics: [inventory_turnover]
```

When the AI sees that ROAS is unusually high one week, it can check `domain_facts` and explain: "Note that Meta's reported ROAS is typically 2-4x higher than warehouse-attributed ROAS, which the dashboard shows separately."

This is what "AI-ready warehouse" actually means in practice — not "the warehouse has an LLM bolted on," but **the warehouse encodes enough domain knowledge for an LLM to give correct, contextual answers**.

---

## 7.14 How consumers query the semantic layer

### Power BI

Power BI connects to dbt's Semantic Layer GraphQL endpoint via the dbt Semantic Layer connector. Once connected:

1. Power BI sees the full list of metrics as fields
2. Drag a metric onto a visual; Power BI calls the Semantic Layer with the dimensions in scope
3. The Semantic Layer returns aggregated data; Power BI renders it

Critically: Power BI **does not compute metrics itself.** It is a thin presentation layer. The metric formulas live in YAML, not DAX.

### The AI assistant (Spark feature, built on top)

The AI assistant uses a different access pattern:

1. User asks "what was our refund rate by category last month?"
2. AI resolves "refund rate" → metric `refund_rate` (synonyms)
3. AI resolves "by category" → dimension `category` on `product_dim`
4. AI resolves "last month" → time grain `month`, offset `1`
5. AI constructs a Semantic Layer GraphQL query
6. AI receives the result and formats a natural-language answer

The ontology, synonyms, and examples all feed this resolution step.

### Ad-hoc SQL

Analysts running ad-hoc queries can either:

- Query the **compiled views** the Semantic Layer materializes (e.g., a Power BI dataset's underlying tables)
- Query the canonical core directly (bypassing the semantic layer)
- Use the dbt Semantic Layer CLI to run a metric query: `dbt sl query --metrics net_revenue --group-by channel`

The pack documents all three patterns. The recommendation: use the Semantic Layer query for anything that will be shared; use direct SQL only for exploration.

### Embedded analytics (v2)

Future embedded dashboards (Section 13 placeholder) will query the Semantic Layer's GraphQL API directly, with row-level security enforced via tenant filters injected at query time. Out of v1 scope but the architecture supports it.

---

## 7.15 Validation and testing

Semantic layer correctness is verified through three test types:

### Test type 1: Semantic model validation

`dbt sl validate` checks that every semantic model is well-formed: every entity references a valid column, every measure references a valid column, every metric references valid measures.

This runs in CI on every PR per Section 4 Part 3 Section 4.44.

### Test type 2: Metric value tests

Specific metric outputs are tested against expected values using the synthetic demo dataset (Section 9 — pending). Example:

```yaml
# tests/semantic_layer/test_gmv_against_known_demo_value.yml
- name: gmv_2026_q1_matches_demo
  metric: gmv
  grain: month
  group_by: []
  filter: "metric_time >= '2026-01-01' AND metric_time <= '2026-03-31'"
  expected_total: 487632.50
```

When the demo data is loaded, GMV for Q1 2026 must equal $487,632.50 exactly. If a model change breaks this, CI fails.

### Test type 3: Glossary completeness

A custom Python script in CI verifies:

- Every metric has a glossary entry (or explicitly opts out via meta tag)
- Every glossary entry references at least one metric or is marked `is_concept_only: true`
- No duplicate metric names across modules

---

## 7.16 What's deferred to v2

Several semantic layer features are deferred:

| Feature | Why deferred |
|---|---|
| Cumulative metrics (running totals) | MetricFlow supports them but no v1 KPI needs them; deferring keeps scope small |
| Conversion metrics (funnel-style) | Requires defining the funnel — out of v1 scope |
| Row-level security at the semantic layer | Needed for embedded analytics, deferred with embedded analytics to v2 |
| Custom calculation contexts | E.g., "show this metric but only for new customers" — workaround in v1 is filtered metric variants |
| LLM-based glossary auto-generation | Future productivity feature |
| Real-time / streaming metrics | Batch only in v1 |
| Multi-currency metric variants | All metrics in reporting currency; native multi-currency views are v2 |

---

## 7.17 Summary

The semantic layer encodes the 25 KPIs from Section 5 as MetricFlow YAML, organized by module (sales, customer, inventory) plus shared definitions and AI metadata. It provides:

- **Metric consistency** across Power BI, the AI assistant, and ad-hoc SQL
- **A business glossary** that defines every term in plain language
- **An entity ontology** that supports machine reasoning over the data model
- **AI metadata** (synonyms, examples, domain facts) that makes natural-language querying robust

Critical design choices:

- The semantic layer lives in the **proprietary** dbt project, not the open-source core — it's where the commercial value concentrates
- Naming is split: technical names (snake_case) for code, labels (Title Case) for display
- Non-additivity is encoded explicitly via `non_additive_dimension`, preventing silent miscounts
- Every metric carries `meta` tags (owner, module, tier, kpi_id) that connect it back to Sections 3, 4, and 5
- The ontology is YAML, not RDF — readable by humans, sufficient for the LLM use case

The next section (Section 8) consolidates governance — ownership, classification, PII handling, and access — that's been touched on throughout but deserves a dedicated home.

---

**Previous:** [Section 6: Connector Specifications](./06_connector_specs.md)
**Next:** [Section 8: Governance Baseline](./08_governance_baseline.md)
