# Section 5: KPI Catalog

> **Document status:** Draft v1
> **Audience:** Engineering team, analytics engineers, business stakeholders, dashboard designers
> **Purpose:** Define every KPI shipped with the Spark Retail Pack — formula, grain, owner, module assignment, source columns, and open-source vs. proprietary classification. This is the contract between the canonical data model (Section 4) and the consumption layer (Sections 7 and 10).

---

## 5.1 Why this catalog matters

The KPI catalog is the **single source of truth** for what a number means in the Spark Retail Pack. Without a catalog:

- "Revenue" means three different things to three different stakeholders
- Each report computes metrics slightly differently
- Reconciliation between dashboards becomes a recurring meeting
- AI assistants give inconsistent answers to "what was our revenue last week"

With this catalog:

- Every metric has one formula, defined once
- The dbt Semantic Layer reads from this catalog and exposes it to Power BI, the AI assistant, and ad-hoc SQL identically
- New metrics extend the catalog; they don't fork it

This section defines **what** each KPI is. Section 7 (Semantic Layer) defines **how** these are encoded in MetricFlow YAML.

---

## 5.2 Catalog structure

Every KPI in this catalog includes the following attributes:

| Attribute | Description |
|---|---|
| **ID** | Stable identifier (e.g., `sales.gmv`) used in semantic layer and code |
| **Name** | Human-readable name (e.g., "Gross Merchandise Value") |
| **Module** | Which analytical module owns it: Sales, Customer 360, or Inventory Health |
| **Type** | `simple` (single aggregation), `ratio` (numerator/denominator), `derived` (computed from other metrics), `cumulative` (running total) |
| **Formula** | The SQL-shaped formula in plain language |
| **Source** | Which fact and column(s) it consumes |
| **Grain support** | Which time grains it supports (daily, weekly, monthly, quarterly, yearly) |
| **Slicers** | Which dimensions it can be sliced by |
| **Owner** | Business team that owns the definition |
| **Tier** | Open Source or Proprietary |
| **Notes** | Edge cases, caveats, calculation nuances |

---

## 5.3 Catalog summary table

All 25 v1 KPIs at a glance.

| # | ID | Name | Module | Type | Tier |
|---|---|---|---|---|---|
| 1 | `sales.gmv` | Gross Merchandise Value | Sales | simple | OSS |
| 2 | `sales.net_revenue` | Net Revenue | Sales | simple | OSS |
| 3 | `sales.order_count` | Order Count | Sales | simple | OSS |
| 4 | `sales.average_order_value` | Average Order Value | Sales | ratio | OSS |
| 5 | `sales.revenue_growth_pct` | Revenue Growth % | Sales | derived | OSS |
| 6 | `sales.refund_rate` | Refund Rate | Sales | ratio | Pro |
| 7 | `sales.return_rate` | Return Rate | Sales | ratio | Pro |
| 8 | `sales.revenue_by_channel` | Revenue by Channel | Sales | simple | Pro |
| 9 | `sales.tax_collected` | Tax Collected | Sales | simple | OSS |
| 10 | `customer.active_customers_30d` | Active Customers (30-day) | Customer 360 | simple | OSS |
| 11 | `customer.active_customers_90d` | Active Customers (90-day) | Customer 360 | simple | OSS |
| 12 | `customer.new_customers` | New Customers | Customer 360 | simple | OSS |
| 13 | `customer.repeat_customer_count` | Repeat Customer Count | Customer 360 | simple | OSS |
| 14 | `customer.repeat_purchase_rate` | Repeat Purchase Rate | Customer 360 | ratio | OSS |
| 15 | `customer.lifetime_value` | Customer Lifetime Value (basic) | Customer 360 | derived | Pro |
| 16 | `customer.avg_time_between_orders` | Average Time Between Orders | Customer 360 | derived | Pro |
| 17 | `customer.cac_by_channel` | Customer Acquisition Cost by Channel | Customer 360 | ratio | Pro |
| 18 | `customer.roas_by_channel` | Return on Ad Spend by Channel | Customer 360 | ratio | Pro |
| 19 | `customer.email_engagement_rate` | Email Engagement Rate | Customer 360 | ratio | Pro |
| 20 | `inventory.total_inventory_value` | Total Inventory Value | Inventory | simple | OSS |
| 21 | `inventory.inventory_turnover` | Inventory Turnover | Inventory | derived | Pro |
| 22 | `inventory.days_of_supply` | Days of Supply | Inventory | derived | OSS |
| 23 | `inventory.stockout_rate` | Stockout Rate | Inventory | ratio | OSS |
| 24 | `inventory.sell_through_rate` | Sell-Through Rate | Inventory | ratio | Pro |
| 25 | `inventory.slow_moving_sku_count` | Slow-Moving SKU Count | Inventory | simple | Pro |

**Distribution by module:** Sales 9, Customer 360 10, Inventory 6 = **25 total** (corrected from the 9/9/7 indicative split in Section 3 — see Section 5.16 for variance explanation).

**Distribution by tier:** Open Source 14, Proprietary 11.

---

## 5.4 Module 1 — Sales Analytics KPIs

### KPI 1: `sales.gmv` — Gross Merchandise Value

| | |
|---|---|
| **Module** | Sales Analytics |
| **Type** | simple |
| **Formula** | `SUM(fact_orders.gross_amount) WHERE order_status NOT IN ('cancelled')` |
| **Source** | `fact_orders.gross_amount` |
| **Grain support** | Daily, Weekly, Monthly, Quarterly, Yearly, Fiscal Year |
| **Slicers** | Channel, Geography, Payment Method, Customer Segment, Date |
| **Owner** | Finance |
| **Tier** | Open Source |
| **Notes** | GMV is *pre-refund* and excludes cancelled orders. Discounts are **included** in GMV reduction (i.e., GMV is after discounts but before refunds). Tax and shipping are excluded. Net revenue (KPI 2) subtracts refunds. |

### KPI 2: `sales.net_revenue` — Net Revenue

| | |
|---|---|
| **Module** | Sales Analytics |
| **Type** | simple |
| **Formula** | `SUM(fact_orders.gross_amount - fact_orders.discount_amount - fact_orders.refunded_amount) WHERE order_status NOT IN ('cancelled')` |
| **Source** | `fact_orders.gross_amount`, `fact_orders.discount_amount`, `fact_orders.refunded_amount` |
| **Grain support** | Daily, Weekly, Monthly, Quarterly, Yearly, Fiscal Year |
| **Slicers** | Channel, Geography, Payment Method, Customer Segment, Date, Product Category |
| **Owner** | Finance |
| **Tier** | Open Source |
| **Notes** | This is the "true" revenue figure — what the business keeps after discounts and refunds. **Tax is excluded** (it's a liability owed to authorities, not revenue) and **shipping is excluded** (it's a pass-through cost). This is the metric reported to investors and the denominator for most retail efficiency ratios. Tips are included for businesses that collect them; clients can configure `vars.include_tips_in_revenue = false` to exclude. |

### KPI 3: `sales.order_count` — Order Count

| | |
|---|---|
| **Module** | Sales Analytics |
| **Type** | simple |
| **Formula** | `COUNT(DISTINCT fact_orders.order_id) WHERE order_status NOT IN ('cancelled')` |
| **Source** | `fact_orders.order_id` |
| **Grain support** | Daily, Weekly, Monthly, Quarterly, Yearly, Fiscal Year |
| **Slicers** | Channel, Geography, Customer Segment, Date, Payment Method |
| **Owner** | Operations |
| **Tier** | Open Source |
| **Notes** | Counts orders, not order lines. Cancelled orders are excluded. Refunded orders **are still counted** — refunding doesn't un-place an order. |

### KPI 4: `sales.average_order_value` — Average Order Value (AOV)

| | |
|---|---|
| **Module** | Sales Analytics |
| **Type** | ratio |
| **Formula** | `sales.net_revenue / sales.order_count` |
| **Source** | Derived from KPIs 2 and 3 |
| **Grain support** | Daily, Weekly, Monthly, Quarterly, Yearly, Fiscal Year |
| **Slicers** | Channel, Geography, Customer Segment, Date, Product Category |
| **Owner** | Marketing |
| **Tier** | Open Source |
| **Notes** | AOV is computed at query time, not stored — slicing GMV/orders by any dimension correctly recomputes AOV for that slice. A common mistake is averaging individual order amounts; this catalog defines AOV as total revenue / total orders, which is correct for analytical slicing. |

### KPI 5: `sales.revenue_growth_pct` — Revenue Growth %

| | |
|---|---|
| **Module** | Sales Analytics |
| **Type** | derived |
| **Formula** | `(sales.net_revenue[current_period] - sales.net_revenue[prior_period]) / sales.net_revenue[prior_period] * 100` |
| **Source** | Derived from KPI 2 |
| **Grain support** | Weekly, Monthly, Quarterly, Yearly, Fiscal Year (not daily — too noisy) |
| **Slicers** | Channel, Geography, Customer Segment, Product Category |
| **Owner** | Finance, CEO |
| **Tier** | Open Source |
| **Notes** | Default comparison is period-over-period (this month vs. last month). Year-over-year comparison ships as a catalog variant: `sales.revenue_growth_yoy_pct` (see Section 5.8). NULL when prior period revenue = 0 (avoids division by zero). |

### KPI 6: `sales.refund_rate` — Refund Rate

| | |
|---|---|
| **Module** | Sales Analytics |
| **Type** | ratio |
| **Formula** | `SUM(fact_refunds.refund_amount) / SUM(fact_orders.gross_amount) * 100` over the same period |
| **Source** | `fact_refunds.refund_amount`, `fact_orders.gross_amount` |
| **Grain support** | Weekly, Monthly, Quarterly, Yearly |
| **Slicers** | Channel, Product Category, Refund Category, Geography |
| **Owner** | Operations, Customer Service |
| **Tier** | Proprietary |
| **Notes** | Refund rate is **percentage of revenue refunded**, not percentage of orders refunded (that's a separate KPI: `sales.orders_with_refund_rate`, which is in v1.5). The matching window is by `refund_date`, not by the date of the underlying order — so refunds in March against February orders are attributed to March. Daily grain is excluded because refund volumes per day are too noisy to be useful. |

### KPI 7: `sales.return_rate` — Return Rate

| | |
|---|---|
| **Module** | Sales Analytics |
| **Type** | ratio |
| **Formula** | `SUM(fact_order_lines.refunded_quantity) / SUM(fact_order_lines.quantity) * 100` |
| **Source** | `fact_order_lines.refunded_quantity`, `fact_order_lines.quantity` |
| **Grain support** | Weekly, Monthly, Quarterly, Yearly |
| **Slicers** | Product, Category, Channel, Geography |
| **Owner** | Operations, Merchandising |
| **Tier** | Proprietary |
| **Notes** | Return rate is **unit-based**, not revenue-based (use refund rate for revenue impact). High return rates by product category often signal quality or sizing issues — this KPI is most useful when sliced by `category`. |

### KPI 8: `sales.revenue_by_channel` — Revenue by Channel

| | |
|---|---|
| **Module** | Sales Analytics |
| **Type** | simple |
| **Formula** | `sales.net_revenue GROUP BY dim_channel.channel_name` |
| **Source** | KPI 2 sliced by `dim_channel.channel_name` |
| **Grain support** | Daily, Weekly, Monthly, Quarterly, Yearly |
| **Slicers** | Date, Geography, Customer Segment |
| **Owner** | Marketing |
| **Tier** | Proprietary |
| **Notes** | Technically derivable from KPI 2 + channel slicer, but exposed as a named metric for dashboard convenience and Power BI ease-of-use. Pro tier because it includes the advanced channel hierarchy (online → marketplace → social → search) from the proprietary channel-mapping seed library. |

### KPI 9: `sales.tax_collected` — Tax Collected

| | |
|---|---|
| **Module** | Sales Analytics |
| **Type** | simple |
| **Formula** | `SUM(fact_orders.tax_amount) WHERE order_status NOT IN ('cancelled')` |
| **Source** | `fact_orders.tax_amount` |
| **Grain support** | Daily, Weekly, Monthly, Quarterly, Yearly, Fiscal Year |
| **Slicers** | Geography (essential), Channel, Date |
| **Owner** | Finance, Tax |
| **Tier** | Open Source |
| **Notes** | Almost always sliced by `dim_geography.country_code` or `state_or_region_code` for tax filing purposes. The pack does **not** compute tax liability (depends on jurisdiction rules); it reports tax collected, which is the input to that calculation. Refunded tax is excluded — clients filing tax should use net_tax = collected - refunded_tax. |

---

## 5.5 Module 2 — Customer 360 KPIs

### KPI 10: `customer.active_customers_30d` — Active Customers (30-day)

| | |
|---|---|
| **Module** | Customer 360 |
| **Type** | simple |
| **Formula** | `COUNT(DISTINCT customer_id) FROM fact_customer_state_daily WHERE snapshot_date = <as-of date> AND is_active_30d = TRUE` |
| **Source** | `fact_customer_state_daily.is_active_30d` |
| **Grain support** | Daily (point-in-time count), Weekly, Monthly |
| **Slicers** | Segment, Geography, Channel of acquisition |
| **Owner** | Growth |
| **Tier** | Open Source |
| **Notes** | "Active" defined as: at least one completed order in the trailing 30 days. **This is a point-in-time count, not a sum** — summing daily values double-counts customers. The semantic layer enforces this by marking it as a non-additive measure across time. |

### KPI 11: `customer.active_customers_90d` — Active Customers (90-day)

| | |
|---|---|
| **Module** | Customer 360 |
| **Type** | simple |
| **Formula** | `COUNT(DISTINCT customer_id) FROM fact_customer_state_daily WHERE snapshot_date = <as-of date> AND is_active_90d = TRUE` |
| **Source** | `fact_customer_state_daily.is_active_90d` |
| **Grain support** | Daily (point-in-time), Weekly, Monthly |
| **Slicers** | Segment, Geography, Channel of acquisition |
| **Owner** | Growth |
| **Tier** | Open Source |
| **Notes** | Same as KPI 10 but with 90-day window — useful for industries with longer purchase cycles (furniture, mattresses). Non-additive across time. |

### KPI 12: `customer.new_customers` — New Customers

| | |
|---|---|
| **Module** | Customer 360 |
| **Type** | simple |
| **Formula** | `COUNT(DISTINCT customer_id) FROM dim_customer WHERE first_order_date BETWEEN <period_start> AND <period_end>` |
| **Source** | `dim_customer.first_order_date` |
| **Grain support** | Daily, Weekly, Monthly, Quarterly, Yearly |
| **Slicers** | Acquisition Channel, Geography, Segment |
| **Owner** | Growth, Marketing |
| **Tier** | Open Source |
| **Notes** | A "new customer" is one whose first **completed order** falls in the period. Customers who registered but never purchased are not counted. This is additive across time at any grain (unlike active customers). |

### KPI 13: `customer.repeat_customer_count` — Repeat Customer Count

| | |
|---|---|
| **Module** | Customer 360 |
| **Type** | simple |
| **Formula** | `COUNT(DISTINCT customer_id) FROM fact_orders WHERE order_date BETWEEN <period_start> AND <period_end> AND is_repeat_order = TRUE` |
| **Source** | `fact_orders.is_repeat_order`, `fact_orders.customer_id` |
| **Grain support** | Daily, Weekly, Monthly, Quarterly, Yearly |
| **Slicers** | Segment, Channel, Geography |
| **Owner** | Growth |
| **Tier** | Open Source |
| **Notes** | A "repeat customer" in this period is one who placed an order in the period **and** had at least one prior order before this period. A customer who placed their 2nd and 3rd order in the same month is counted once. |

### KPI 14: `customer.repeat_purchase_rate` — Repeat Purchase Rate

| | |
|---|---|
| **Module** | Customer 360 |
| **Type** | ratio |
| **Formula** | `customer.repeat_customer_count / (customer.new_customers + customer.repeat_customer_count) * 100` |
| **Source** | Derived from KPIs 12 and 13 |
| **Grain support** | Weekly, Monthly, Quarterly, Yearly |
| **Slicers** | Segment, Channel, Geography, Product Category |
| **Owner** | Growth |
| **Tier** | Open Source |
| **Notes** | The denominator is "customers who purchased in this period" (new + repeat); the numerator is the repeat subset. A common alternative is `repeat_customers / total_lifetime_customers`, which produces very different numbers — this catalog uses the period-based definition because it's actionable for marketing teams. |

### KPI 15: `customer.lifetime_value` — Customer Lifetime Value (basic)

| | |
|---|---|
| **Module** | Customer 360 |
| **Type** | derived |
| **Formula** | `AVG(fact_customer_state_daily.lifetime_revenue) WHERE snapshot_date = <as-of date>` |
| **Source** | `fact_customer_state_daily.lifetime_revenue` |
| **Grain support** | Daily (point-in-time), Monthly |
| **Slicers** | Segment, Acquisition Channel, Acquisition Cohort (month), Geography |
| **Owner** | Growth |
| **Tier** | Proprietary |
| **Notes** | **This is "LTV-to-date," not predictive LTV.** It answers "how much have our customers spent on average?" not "how much will they spend?". Most useful when sliced by acquisition cohort to compare cohort performance over time. The predictive variant (`customer.predicted_ltv`) is in the proprietary cohort module (Pro tier, v2). |

### KPI 16: `customer.avg_time_between_orders` — Average Time Between Orders

| | |
|---|---|
| **Module** | Customer 360 |
| **Type** | derived |
| **Formula** | `AVG(days between consecutive orders) FROM fact_orders WHERE customer has 2+ orders` |
| **Source** | `fact_orders.order_date` partitioned by `customer_id` |
| **Grain support** | Monthly, Quarterly, Yearly |
| **Slicers** | Segment, Product Category, Acquisition Cohort |
| **Owner** | Growth |
| **Tier** | Proprietary |
| **Notes** | Only computed for customers with 2+ orders (avoids meaningless NULL). The window is calculated within the period — e.g., for "Q2 average time between orders," only consecutive orders that both fall in Q2 are counted. This is conservative but consistent. |

### KPI 17: `customer.cac_by_channel` — Customer Acquisition Cost by Channel

| | |
|---|---|
| **Module** | Customer 360 |
| **Type** | ratio |
| **Formula** | `SUM(fact_marketing_spend.spend_amount) / COUNT(DISTINCT new customers attributed to channel)` |
| **Source** | `fact_marketing_spend.spend_amount`, attribution via UTM matching to `dim_customer.acquisition_channel` |
| **Grain support** | Weekly, Monthly, Quarterly |
| **Slicers** | Channel (required), Date, Geography |
| **Owner** | Marketing |
| **Tier** | Proprietary |
| **Notes** | Attribution uses **last-touch by default** in v1 (the channel that drove the new customer's first purchase). Multi-touch attribution is a v2 module. CAC for organic channels = 0 in v1 (since there's no spend); future versions may add allocated overhead. CAC for "direct" traffic = NULL (cannot be attributed). |

### KPI 18: `customer.roas_by_channel` — Return on Ad Spend by Channel

| | |
|---|---|
| **Module** | Customer 360 |
| **Type** | ratio |
| **Formula** | `SUM(revenue attributed to channel) / SUM(fact_marketing_spend.spend_amount) * 100` |
| **Source** | `fact_marketing_spend.spend_amount`, attribution via UTM matching to orders |
| **Grain support** | Weekly, Monthly, Quarterly |
| **Slicers** | Channel (required), Date, Geography, Campaign |
| **Owner** | Marketing |
| **Tier** | Proprietary |
| **Notes** | This is the warehouse-attributed ROAS, **not the platform-reported ROAS** (which is typically 2–4× higher due to attribution windows and overlap). Reporting both side-by-side is a common Power BI pattern; this catalog defines only the warehouse-attributed version. Same last-touch attribution as KPI 17. |

### KPI 19: `customer.email_engagement_rate` — Email Engagement Rate

| | |
|---|---|
| **Module** | Customer 360 |
| **Type** | ratio |
| **Formula** | `COUNT(events WHERE event_type IN ('opened', 'clicked')) / COUNT(events WHERE event_type = 'delivered') * 100` |
| **Source** | `fact_email_engagement.event_type` |
| **Grain support** | Daily, Weekly, Monthly |
| **Slicers** | Email Campaign, Customer Segment, Geography |
| **Owner** | Marketing (Email) |
| **Tier** | Proprietary |
| **Notes** | Engagement = opens + clicks. Some clients prefer "click rate" (clicks / delivered) or "open rate" (opens / delivered) as separate metrics — these are catalog variants in the proprietary email module. Apple Mail Privacy Protection inflates open rates; this is documented in the dashboard but not adjusted in the metric (clients can adjust via a config flag). |

---

## 5.6 Module 3 — Inventory Health KPIs

### KPI 20: `inventory.total_inventory_value` — Total Inventory Value

| | |
|---|---|
| **Module** | Inventory Health |
| **Type** | simple |
| **Formula** | `SUM(fact_inventory_snapshot.inventory_value) WHERE snapshot_date = <as-of date>` |
| **Source** | `fact_inventory_snapshot.inventory_value` (which is `quantity_on_hand × unit_cost`) |
| **Grain support** | Daily (point-in-time), Weekly, Monthly |
| **Slicers** | Category, Location, Brand, Supplier (when supplier dim exists) |
| **Owner** | Operations, Finance |
| **Tier** | Open Source |
| **Notes** | This is **inventory value at cost**, not at retail. For retail-value inventory, use `inventory.total_inventory_retail_value` (catalog variant in Pro tier). Non-additive across time (point-in-time snapshot). NULL when client doesn't track `unit_cost` — surfaces as a data quality alert. |

### KPI 21: `inventory.inventory_turnover` — Inventory Turnover

| | |
|---|---|
| **Module** | Inventory Health |
| **Type** | derived |
| **Formula** | `COGS over period / AVG(fact_inventory_snapshot.inventory_value) over same period`, annualized |
| **Source** | `fact_order_lines.unit_cost × quantity` (for COGS), `fact_inventory_snapshot.inventory_value` (for average inventory) |
| **Grain support** | Monthly, Quarterly, Yearly |
| **Slicers** | Category, Location, Brand |
| **Owner** | Operations, Merchandising |
| **Tier** | Proprietary |
| **Notes** | Annualized to make periods comparable: monthly turnover × 12, quarterly × 4. Industry benchmark for retail is 4–8 turns/year. NULL when COGS data is missing. Sliced by `category` is the most actionable view — high turnover categories are working capital efficient; low turnover signals overstock. |

### KPI 22: `inventory.days_of_supply` — Days of Supply

| | |
|---|---|
| **Module** | Inventory Health |
| **Type** | derived |
| **Formula** | `fact_inventory_snapshot.quantity_available / avg_daily_sales_rate_28d` |
| **Source** | `fact_inventory_snapshot.days_of_supply` (already computed in the fact) |
| **Grain support** | Daily (point-in-time), Weekly |
| **Slicers** | SKU, Category, Location |
| **Owner** | Operations |
| **Tier** | Open Source |
| **Notes** | The 28-day average sales rate is the denominator. NULL when no sales in the prior 28 days (slow movers — flagged separately via KPI 25). Most actionable as an at-SKU level alert: SKUs with <14 days of supply should trigger reorder review. |

### KPI 23: `inventory.stockout_rate` — Stockout Rate

| | |
|---|---|
| **Module** | Inventory Health |
| **Type** | ratio |
| **Formula** | `COUNT(SKUs WHERE is_out_of_stock = TRUE) / COUNT(DISTINCT SKUs) * 100` for the period |
| **Source** | `fact_inventory_snapshot.is_out_of_stock` |
| **Grain support** | Daily, Weekly, Monthly |
| **Slicers** | Category, Location |
| **Owner** | Operations |
| **Tier** | Open Source |
| **Notes** | Daily stockout rate: % of SKUs at zero stock at end of day. Period stockout rate (weekly/monthly): % of SKUs that experienced **at least one** stockout day in the period. Both variants ship as separate IDs: `inventory.stockout_rate_eod` and `inventory.stockout_rate_period`. |

### KPI 24: `inventory.sell_through_rate` — Sell-Through Rate

| | |
|---|---|
| **Module** | Inventory Health |
| **Type** | ratio |
| **Formula** | `units_sold / (units_sold + units_remaining) * 100` over a fixed period (typically 30, 60, or 90 days from receipt) |
| **Source** | `fact_inventory_movements` (receipts), `fact_order_lines.quantity` (sales) |
| **Grain support** | Monthly, Quarterly |
| **Slicers** | Category, Brand, Season Cohort (when applicable) |
| **Owner** | Merchandising |
| **Tier** | Proprietary |
| **Notes** | Sell-through is **cohort-based**: tracks a batch of SKUs received on a specific date and measures the % sold over a window. The pack defaults to a 60-day sell-through window; clients can configure (typical fashion retailers: 30 days; durable goods: 90+ days). Pro tier because the cohort logic is the proprietary IP. |

### KPI 25: `inventory.slow_moving_sku_count` — Slow-Moving SKU Count

| | |
|---|---|
| **Module** | Inventory Health |
| **Type** | simple |
| **Formula** | `COUNT(DISTINCT SKUs WHERE is_slow_mover = TRUE) FROM fact_inventory_snapshot WHERE snapshot_date = <as-of date>` |
| **Source** | `fact_inventory_snapshot.is_slow_mover` (Pro column — TRUE when no sales in trailing 60 days) |
| **Grain support** | Daily (point-in-time), Weekly, Monthly |
| **Slicers** | Category, Location, Brand |
| **Owner** | Merchandising, Operations |
| **Tier** | Proprietary |
| **Notes** | The 60-day threshold is the default; configurable via `vars.slow_mover_days` (default 60). Each slow-moving SKU represents working capital tied up; the financial impact view (`SUM(inventory_value WHERE is_slow_mover = TRUE)`) is a derived catalog variant. |

---

## 5.7 Cross-cutting concerns

### Period definitions

Every period-based KPI uses the date conventions defined in `dim_date` (Section 4.5):

| Period | Definition |
|---|---|
| Daily | Calendar day, client's reporting timezone |
| Weekly | Monday–Sunday by default; configurable via `vars.week_start_day` |
| Monthly | Calendar month |
| Quarterly | Calendar quarter by default; fiscal quarter supported |
| Yearly | Calendar year by default; fiscal year supported |
| MTD/QTD/YTD | Inclusive of today, computed from `dim_date.is_mtd/is_qtd/is_ytd` flags |
| Trailing 30/90 days | Inclusive of today, looking back 30 or 90 calendar days |

### Cancelled orders

**All sales KPIs exclude cancelled orders** unless explicitly noted. Refunded orders are still counted in order count and GMV (refunding doesn't un-place an order); they're netted out in net revenue.

### Currency

All currency amounts are in the client's reporting currency, converted at silver layer (Section 4 Part 1, Section 4.2). KPIs do not handle FX.

### Non-additive measures

Several measures are non-additive across time grains and the semantic layer marks them as such:

| Measure | Why non-additive |
|---|---|
| Active customers (30/90d) | Same customer counted on multiple consecutive days |
| Total inventory value | Point-in-time snapshot |
| LTV-to-date | Point-in-time aggregate |
| Slow-moving SKU count | Point-in-time count |

For non-additive measures, the semantic layer prevents accidental sums (e.g., "total active customers in March" is not the sum of daily active customer counts). The default aggregation across time is "last value of the period" or "average of the period," depending on the metric.

### NULL handling

Each KPI's notes section documents NULL behavior. The general rule: **a NULL metric value is never silently converted to 0.** A KPI that cannot be computed (missing cost data, no prior period for growth %, no sales for time-between-orders) returns NULL and the dashboard displays "—" or "N/A," never "$0.00."

---

## 5.8 The metric variants pattern

Several KPIs have natural variants (e.g., refund rate by revenue vs. by order count). Rather than list every variant as a separate KPI in v1 and bloat the catalog, the pack uses a **base metric + variants** pattern:

- **Base metric** (in v1 catalog): the most commonly requested definition
- **Variant metrics** (in extended catalog, ships with v1 as documentation only): alternative definitions, callable from the semantic layer as `<base>_<variant>`

Example variants documented but not detailed in v1:

| Base | Variants |
|---|---|
| `sales.revenue_growth_pct` | `sales.revenue_growth_yoy_pct` (year-over-year), `sales.revenue_growth_wow_pct` (week-over-week) |
| `sales.refund_rate` | `sales.refund_rate_by_order_count`, `sales.refund_rate_excl_chargebacks` |
| `sales.return_rate` | `sales.return_rate_by_category`, `sales.return_rate_excl_subscription` |
| `customer.lifetime_value` | `customer.lifetime_value_excluding_returns`, `customer.lifetime_value_first_year` |
| `inventory.stockout_rate` | `inventory.stockout_rate_eod`, `inventory.stockout_rate_period` |

Variants are first-class once added to the catalog; in v1 they ship as YAML stubs in the proprietary semantic layer package, ready for clients to enable.

---

## 5.9 KPI-to-fact dependency matrix

A consolidated view of which KPI consumes which fact table — useful for understanding rebuild scope.

| KPI | fact_orders | fact_order_lines | fact_refunds | fact_marketing_spend | fact_web_sessions | fact_email_engagement | fact_customer_state_daily | fact_inventory_snapshot | fact_inventory_movements |
|---|---|---|---|---|---|---|---|---|---|
| GMV | ✓ | | | | | | | | |
| Net Revenue | ✓ | | | | | | | | |
| Order Count | ✓ | | | | | | | | |
| AOV | ✓ | | | | | | | | |
| Revenue Growth % | ✓ | | | | | | | | |
| Refund Rate | ✓ | | ✓ | | | | | | |
| Return Rate | | ✓ | | | | | | | |
| Revenue by Channel | ✓ | | | | | | | | |
| Tax Collected | ✓ | | | | | | | | |
| Active Customers 30d | | | | | | | ✓ | | |
| Active Customers 90d | | | | | | | ✓ | | |
| New Customers | ✓ | | | | | | | | |
| Repeat Customer Count | ✓ | | | | | | | | |
| Repeat Purchase Rate | ✓ | | | | | | | | |
| LTV (basic) | | | | | | | ✓ | | |
| Avg Time Between Orders | ✓ | | | | | | | | |
| CAC by Channel | | | | ✓ | ✓ | | | | |
| ROAS by Channel | ✓ | | | ✓ | ✓ | | | | |
| Email Engagement Rate | | | | | | ✓ | | | |
| Total Inventory Value | | | | | | | | ✓ | |
| Inventory Turnover | | ✓ | | | | | | ✓ | |
| Days of Supply | | | | | | | | ✓ | |
| Stockout Rate | | | | | | | | ✓ | |
| Sell-Through Rate | | ✓ | | | | | | | ✓ |
| Slow-Moving SKU Count | | | | | | | | ✓ | |

**Most depended-on facts:** `fact_orders` (10 KPIs), `fact_inventory_snapshot` (5 KPIs), `fact_customer_state_daily` (3 KPIs).

**Implication for incremental builds:** a refresh of `fact_orders` invalidates 10 KPIs; a refresh of `fact_email_engagement` invalidates only 1. The semantic layer can use this dependency map to invalidate cached metric values selectively.

---

## 5.10 KPI-to-dimension slicer matrix

A consolidated view of which dimensions slice which KPIs.

| KPI | Date | Customer | Product | Channel | Geography | Payment Method | Campaign |
|---|---|---|---|---|---|---|---|
| GMV | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | |
| Net Revenue | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | |
| Order Count | ✓ | ✓ | | ✓ | ✓ | ✓ | |
| AOV | ✓ | ✓ | ✓ | ✓ | ✓ | | |
| Revenue Growth % | ✓ | ✓ | ✓ | ✓ | ✓ | | |
| Refund Rate | ✓ | | ✓ | ✓ | ✓ | | |
| Return Rate | ✓ | | ✓ | ✓ | ✓ | | |
| Revenue by Channel | ✓ | ✓ | | ✓ | ✓ | | |
| Tax Collected | ✓ | | | ✓ | ✓ | | |
| Active Customers 30d/90d | ✓ | ✓ | | ✓ | ✓ | | |
| New Customers | ✓ | ✓ | | ✓ | ✓ | | |
| Repeat Customer Count | ✓ | ✓ | | ✓ | ✓ | | |
| Repeat Purchase Rate | ✓ | ✓ | ✓ | ✓ | ✓ | | |
| LTV (basic) | ✓ | ✓ | | ✓ | ✓ | | |
| Avg Time Between Orders | ✓ | ✓ | ✓ | | | | |
| CAC by Channel | ✓ | | | ✓ | ✓ | | ✓ |
| ROAS by Channel | ✓ | | | ✓ | ✓ | | ✓ |
| Email Engagement Rate | ✓ | ✓ | | | ✓ | | ✓ |
| Total Inventory Value | ✓ | | ✓ | | | | |
| Inventory Turnover | ✓ | | ✓ | | ✓ (Location) | | |
| Days of Supply | ✓ | | ✓ | | ✓ (Location) | | |
| Stockout Rate | ✓ | | ✓ | | ✓ (Location) | | |
| Sell-Through Rate | ✓ | | ✓ | | | | |
| Slow-Moving SKU Count | ✓ | | ✓ | | ✓ (Location) | | |

---

## 5.11 Ownership and stewardship

Every KPI has a **business owner** (the team that defines what the metric should mean) and a **technical steward** (the team that maintains the implementation).

| Owner | KPIs they own | Why |
|---|---|---|
| **Finance** | GMV, Net Revenue, Revenue Growth %, Tax Collected, Total Inventory Value | These feed financial reporting and board metrics |
| **Operations** | Order Count, Refund Rate, Return Rate, Stockout Rate, Days of Supply, Total Inventory Value (co-owner) | Operational health and customer experience |
| **Growth/Marketing** | AOV, New Customers, Repeat Customer Count, Repeat Purchase Rate, Active Customers (30/90d), LTV, CAC, ROAS, Email Engagement, Revenue by Channel | Customer acquisition and retention |
| **Merchandising** | Return Rate (co-owner), Inventory Turnover, Sell-Through Rate, Slow-Moving SKU Count | Product mix decisions |
| **Customer Service** | Refund Rate (co-owner) | Insight into customer-driven issues |

**Technical steward for all KPIs:** Spark Analytics implementation team (for client deployments) or the client's analytics engineering team (post-handoff).

Changes to KPI definitions require sign-off from the business owner. Pure technical changes (performance, query rewrite) require only steward approval.

---

## 5.12 KPI evolution policy

KPIs are part of the pack's public contract with clients. Changes follow semantic versioning (Section 4 Part 3, Section 4.38):

| Change type | Example | Version impact |
|---|---|---|
| Adding a new KPI | Adding `customer.predicted_churn` | Minor version bump |
| Adding a slicer dimension to existing KPI | Adding Brand to Refund Rate slicers | Minor |
| Changing a formula's interpretation | Changing AOV from net to gross | **Major** — breaking |
| Renaming a KPI ID | `sales.gmv` → `sales.gross_merchandise_value` | **Major** — breaking |
| Adding a NULL handling rule | Returning NULL instead of 0 for missing data | Minor (documented in release notes) |
| Performance improvement to underlying SQL | Switching to a window function | Patch (no behavior change) |

Deprecated KPIs are kept callable for 2 major versions before removal. Replacement KPIs are added alongside, not in place of, the old one.

---

## 5.13 What's deliberately not in v1

Several KPIs that retailers commonly ask for are deferred to v2 or later. Each is documented with reasoning:

| Deferred KPI | Why deferred |
|---|---|
| **Gross margin %** | Requires `unit_cost` populated for every SKU. Many clients don't track Shopify cost reliably. Available as a v1 "advanced" KPI when cost data is present; not a default. |
| **Contribution margin** | Requires allocated overhead (shipping cost, payment processing fees) — too varied across clients for a one-size-fits-all formula. v2 |
| **Multi-touch attribution metrics** | First/last-touch ships in v1 (KPIs 17–18); multi-touch (linear, U-shaped, data-driven) is a v2 attribution module |
| **Predictive LTV** | Requires a trained model. Pro v2 module |
| **Churn probability** | Same as predictive LTV — requires ML. Pro v2 |
| **Customer health score** | Composite of engagement signals — varies enormously by business model. Pro v2 with config |
| **Net Promoter Score (NPS)** | Requires survey integration — not in v1 connector set |
| **Cart abandonment rate** | Requires cart events from storefront platforms — needs deeper Shopify integration. v2 |
| **Subscription / recurring revenue metrics** | Subscription module deferred entirely. v2 |
| **Fulfillment SLA metrics** | Fulfillment module deferred. v2 |
| **Customer service KPIs (resolution time, CSAT)** | Requires Zendesk/Gorgias connector. v2 |
| **Loyalty program metrics** | Loyalty platform connectors deferred. v2 |

---

## 5.14 KPI-to-Power BI dashboard mapping

A preview of which KPIs surface on which dashboards (full dashboard design in Section 10):

| Dashboard | KPIs featured |
|---|---|
| **Executive Summary** | GMV, Net Revenue, Order Count, AOV, Revenue Growth %, New Customers, Active Customers 30d, Revenue by Channel, Total Inventory Value |
| **Customer 360** | Active Customers (30/90d), New Customers, Repeat Customer Count, Repeat Purchase Rate, LTV, Avg Time Between Orders, CAC by Channel, ROAS by Channel, Email Engagement Rate |
| **Inventory Health** | Total Inventory Value, Inventory Turnover, Days of Supply, Stockout Rate, Sell-Through Rate, Slow-Moving SKU Count |

KPIs that appear on multiple dashboards (e.g., GMV on both Executive and an Operations drill-through) are computed once in the semantic layer and read from there.

---

## 5.15 Open-source vs. Pro distribution rationale

Of 25 KPIs: 14 are open-source, 11 are proprietary. The split is deliberate:

**Open source includes:**

- All foundational sales metrics (GMV, Net Revenue, Order Count, AOV, Revenue Growth %, Tax)
- Basic customer counts (active, new, repeat)
- Repeat purchase rate
- Basic inventory metrics (value, days of supply, stockout rate)

**Proprietary includes:**

- All ratio metrics requiring multi-source joins (Refund Rate joins orders+refunds; CAC joins spend+attribution)
- All metrics requiring proprietary enrichment (LTV uses pro RFM tiers; ROAS uses pro attribution logic)
- All metrics tied to advanced fact columns (Slow-Moving SKUs require the pro `is_slow_mover` flag)
- Inventory metrics requiring proprietary cohort logic (Sell-Through, Turnover)

**Rationale:** The open-source tier delivers a complete, usable sales analytics view that any retailer can stand up for free. The proprietary tier adds the marketing/customer/inventory intelligence that drives actual business decisions — the IP that's hardest to replicate and most valuable to clients.

A retailer running only the open-source tier gets a credible warehouse and basic dashboards. They get the advanced "why is customer acquisition costing us 2× more this month" insights only with the proprietary tier — which is exactly the upsell path.

---

## 5.16 Variance from Section 3's indicative KPI counts

Section 3 indicated 9 KPIs for Sales, 9 for Customer 360, 7 for Inventory (= 25 total). The actual catalog distributes them 9/10/6:

| Module | Section 3 estimate | Section 5 final | Reason for variance |
|---|---|---|---|
| Sales | 9 | 9 | Same |
| Customer 360 | 9 | 10 | Split active customers into 30-day and 90-day (two grains, two KPIs) |
| Inventory | 7 | 6 | Removed "Overstock Value" — derivable as a slicer on Slow-Moving SKU Count, not a separate KPI |

Total remains 25.

---

## 5.17 Summary

Twenty-five KPIs, distributed across three modules, with a clear open-source / proprietary split protecting commercial value while delivering a usable free tier.

Every KPI in this catalog has:

- A stable ID, formula, and source mapping
- Explicit grain support and slicer compatibility
- Documented NULL behavior and edge cases
- Named business owner
- Defined evolution policy

This catalog is the contract between Section 4 (the canonical data model) and Section 7 (the semantic layer that exposes these to consumers).

---

**Previous:** [Section 4 — Part 3: Implementation Standards and Best Practices](./04_canonical_data_model_part3_implementation_standards.md)
**Next:** [Section 6: Connector Specifications](./06_connector_specs.md)
