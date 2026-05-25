# Section 10: Power BI Dashboard Pack

> **Document status:** Draft v1
> **Audience:** Dashboard developers, design team, sales team, technical implementation partners, client BI teams
> **Purpose:** Define the three Power BI dashboard packs that ship with the Spark Retail Pack — their pages, visuals, drill-through patterns, filtering, styling, and connection model. This is the consumption layer that surfaces Sections 5 (KPIs), 7 (semantic layer), and 9 (demo data) to actual users.

---

## 10.1 What this section defines

For each of the three Power BI dashboards shipped with v1, this section specifies:

1. **Purpose and audience** — who uses it and what questions it answers
2. **Page-by-page design** — every page with its visuals, KPIs, and slicers
3. **Drill-through paths** — how users navigate from summary to detail
4. **Filtering and slicer behavior** — what filters apply where
5. **Connection model** — how Power BI connects to Snowflake via the Semantic Layer
6. **Styling and theming** — visual consistency rules
7. **Performance budgets** — query response time expectations
8. **Distribution** — how `.pbix` files ship with the pack

The full visual designs (color palettes, typography, exact pixel layouts) live in the design system files in `04_dashboards/themes/`. This section specifies **what** is on each page and **why**, not the exact visual styling.

---

## 10.2 Why dashboards are part of the pack

A canonical data model and a semantic layer are necessary but not sufficient. Without dashboards:

- A prospect's first impression is "looks like a lot of work to build the actual reports"
- A client's executives have nowhere to look on Monday morning
- The pack's KPI catalog is theoretical, not visible
- The demo (Section 9) has nothing to demo

Shipping pre-built dashboards converts the pack from a foundation into a product. It's also where most of the **proprietary commercial value concentrates** — well-designed dashboards take weeks of work that clients can't easily replicate just by reading the dbt code.

Per Section 11 (pending) and earlier decisions: **all three dashboard packs are proprietary**. They are not in the open-source distribution. A client can install the OSS core and build their own dashboards; the pre-built Power BI files are part of the paid tier.

---

## 10.3 The three dashboards in v1

| # | Dashboard | Primary audience | Pages | Refresh frequency |
|---|---|---|---|---|
| 1 | **Executive Summary** | CEO, CFO, board | 5 | Daily (typically 6:00 AM client time) |
| 2 | **Customer 360** | CMO, Head of Growth, marketing team | 5 | Daily |
| 3 | **Inventory Health** | COO, Head of Operations, supply chain | 5 | Daily |

Each dashboard maps to one of the three modules (Section 3) and one of the three marts (`MART_SALES`, `MART_CUSTOMER`, `MART_INVENTORY`). They share dimensions (date, customer, product) but are otherwise independent — a client adopting only one module gets only its dashboard.

### Why three and not more

Section 1.5's MVP scope was explicit: three dashboard packs in v1. Resisting scope creep here matters. Each additional dashboard adds 1–2 weeks of design and testing work. Three is the minimum that covers the foundational questions every D2C retailer asks weekly; anything beyond that risks shipping no dashboards rather than a small, polished set.

Additional dashboards (Marketing Attribution, Customer Service, Fulfillment Operations) are deferred to v2, aligned with the deferred modules from Section 3.8.

---

## 10.4 Dashboard 1 — Executive Summary

### Purpose

A single dashboard that gives the CEO and CFO a complete picture of the business in five pages, 30 seconds per page. Designed to be the **only dashboard a non-technical executive needs**.

### Primary audience

- **CEO** — owns the business; needs revenue, growth, and inventory at-a-glance
- **CFO** — owns the numbers; needs revenue, refunds, tax, channel mix
- **Board** — periodic review; needs trend context

### Pages

**Page 1 — Overview**

The single-page summary. Loads in <3 seconds. Designed to be the first thing seen.

| Visual | KPIs displayed | Slicer interactions |
|---|---|---|
| KPI card row (top) | Net Revenue (today, MTD, YTD), GMV (YTD), Order Count (MTD), AOV (MTD) | Date range filter |
| Revenue trend line | Net Revenue, last 90 days, daily grain with 7-day moving average | Date, channel |
| Period comparison cards | Current MTD vs. Last MTD; Current QTD vs. Last QTD; Current YTD vs. Last YTD | Date |
| Top 5 channels donut | Revenue by Channel, current month | — |
| Refund rate indicator | Refund Rate (MTD), with arrow vs. prior month | Date |

**Visual layout:** KPI cards across top (1 row), main trend chart middle-left (60% width), period comparisons middle-right (40%), bottom row split between channels and refund indicator.

**Page 2 — Revenue Trends**

Detailed revenue analysis across time and dimensions.

| Visual | KPIs displayed | Notes |
|---|---|---|
| Revenue by month, last 13 months | Net Revenue + Revenue Growth % | Bar chart with growth % labels |
| Revenue by week, last 52 weeks | Net Revenue | Line chart |
| Revenue by day-of-week heatmap | Net Revenue average | Identifies weekly seasonality |
| Revenue YoY comparison | Net Revenue current vs. prior year, monthly | Two lines on same chart |
| Cumulative revenue YTD vs. prior YTD | Cumulative Net Revenue | Two-line chart |

**Page 3 — Channels & Geography**

Where revenue comes from.

| Visual | KPIs displayed | Notes |
|---|---|---|
| Revenue by channel, last 30 days | Revenue by Channel | Horizontal bar chart |
| Channel mix over time | Revenue by Channel, monthly stacked | 12-month stacked bar |
| Revenue map by country | Net Revenue | Filled map |
| Top 10 regions | Net Revenue, current month | Bar chart |
| Channel performance scorecard | Net Revenue, Order Count, AOV per channel | Table with conditional formatting |

**Page 4 — Products**

What's selling.

| Visual | KPIs displayed | Notes |
|---|---|---|
| Top 20 SKUs by revenue, MTD | Net Revenue, Quantity Sold | Bar chart |
| Category performance | Net Revenue by category, last 90 days | Bar chart with prior period comparison |
| Category trends | Net Revenue by category, monthly | Multi-line chart, last 13 months |
| Slow-moving SKUs section | Slow-Moving SKU Count, Total Value at Risk | Cards + drill-through to inventory dashboard |
| Brand performance | Net Revenue by brand, MTD | Table |

**Page 5 — Refunds & Returns**

The honest mirror to revenue.

| Visual | KPIs displayed | Notes |
|---|---|---|
| Refund Rate trend, last 13 months | Refund Rate | Line chart |
| Refund volume by month | Sum of refund_amount | Bar chart |
| Refund reasons breakdown | Refund counts by category | Donut chart |
| Returns by category | Return Rate by category | Bar chart |
| Highest-return SKUs | Top 10 SKUs by return rate, last 90 days | Table |

### Drill-through patterns

Drill-through paths from Executive Summary:

- **From Page 1 KPI card "Refund Rate"** → Page 5 (filtered to current month)
- **From Page 1 "Top 5 channels"** → Page 3 (filtered to selected channel)
- **From Page 4 "Slow-moving SKUs"** → opens Inventory Health Dashboard (cross-dashboard navigation)
- **From Page 4 "Top SKUs"** → Power BI tooltip with product details (image, category, current stock, recent reviews)

### Slicers and global filters

Every page has a global date slicer (default: last 90 days). Page-specific slicers:

- Page 2: channel slicer
- Page 3: country slicer (multi-select)
- Page 4: category slicer
- Page 5: refund category slicer

---

## 10.5 Dashboard 2 — Customer 360

### Purpose

Surface customer behavior, segment health, acquisition efficiency, and retention. The dashboard that powers most weekly meetings of marketing and growth teams.

### Primary audience

- **CMO / Head of Growth** — owns acquisition and retention; needs CAC, LTV, segment health
- **Marketing manager** — owns specific channels and campaigns
- **Email marketing lead** — Klaviyo-specific performance
- **Customer service lead** — relevant for understanding refund/return drivers

### Pages

**Page 1 — Customer Overview**

Top-level customer health.

| Visual | KPIs displayed |
|---|---|
| KPI cards row | Active Customers (30-day), Active Customers (90-day), New Customers (MTD), Repeat Customer Count (MTD), Repeat Purchase Rate (MTD) |
| Active customers trend, 13 months | Active Customers (30-day) |
| New vs. repeat customers stacked | New Customers, Repeat Customer Count, monthly |
| Customer status breakdown | Count of customers by status (active, dormant, churned) |
| Acquisition channels donut | New Customers by acquisition_channel |

**Page 2 — Segments**

Segment composition and movement.

| Visual | KPIs displayed |
|---|---|
| Segment distribution today | Count by customer_segment (One-time, Casual, Loyal, VIP) |
| Segment movement over time | Stacked area, last 6 months — shows customers moving between segments |
| LTV by segment | Customer Lifetime Value by segment |
| AOV by segment | Average Order Value by segment |
| Top segments by lifetime spend | Bar chart |

**Page 3 — Acquisition**

CAC, sources, and campaign performance.

| Visual | KPIs displayed |
|---|---|
| CAC by channel, last 90 days | Customer Acquisition Cost by Channel |
| ROAS by channel, last 90 days | Return on Ad Spend by Channel |
| Spend vs. customers acquired, by channel | Dual-axis: spend bar, customers line |
| Campaign performance table | Per-campaign: spend, customers acquired, CAC, ROAS |
| Acquisition funnel | Sessions → Conversions → New Customers — by channel |

**Page 4 — Retention**

Cohort retention and repeat behavior.

| Visual | KPIs displayed |
|---|---|
| Cohort retention matrix | Monthly cohorts × month-since-acquisition, with order count or revenue |
| Repeat Purchase Rate trend, 13 months | Repeat Purchase Rate |
| Average time between orders, by segment | Avg Time Between Orders |
| Top reasons for churn (proxy) | Inferred from non-purchase periods + email disengagement |
| At-risk customer count | Customers in dormant status, declining trend |

**Page 5 — Email Engagement**

Klaviyo-specific performance.

| Visual | KPIs displayed |
|---|---|
| Email Engagement Rate trend | Email Engagement Rate |
| Top campaigns by engagement | Campaign performance table |
| Subscriber growth trend | Sum of email_subscribed = TRUE over time |
| Email opens vs. clicks vs. conversions | Stacked bar by campaign |
| Disengagement signals | Unsubscribe rate, bounce rate |

### Drill-through patterns

- **From Page 1 "Active Customers 30-day"** → Page 4 (cohort analysis)
- **From Page 2 segment** → Page 4 (cohort matrix filtered to selected segment)
- **From Page 3 campaign row** → Detail page with campaign-specific creative, copy, audience
- **From Page 4 cohort cell** → drill-through to list of customers in that cohort (PII-restricted; only accessible to PII viewer role)
- **From Page 5 campaign row** → Klaviyo campaign-level detail

### Slicers and global filters

- Global: date range (default: last 90 days)
- Page 2: segment multi-select
- Page 3: channel multi-select
- Page 4: cohort month range
- Page 5: campaign type filter (campaign / flow / transactional)

---

## 10.6 Dashboard 3 — Inventory Health

### Purpose

Visibility into stock position, movement, efficiency, and risk. Designed for operations and supply chain teams making daily decisions about purchasing, allocation, and clearance.

### Primary audience

- **COO / Head of Operations** — owns operational efficiency
- **Supply Chain manager** — owns purchasing and replenishment
- **Merchandising team** — owns assortment and category mix
- **Finance** — for inventory valuation and write-down analysis

### Pages

**Page 1 — Stock Position Overview**

Current state of inventory.

| Visual | KPIs displayed |
|---|---|
| KPI cards row | Total Inventory Value, Inventory Turnover (annual), Days of Supply (weighted avg), Stockout Rate (today), Slow-Moving SKU Count |
| Inventory value trend, 13 months | Total Inventory Value, monthly |
| Inventory value by category | Bar chart with conditional color (over/under thresholds) |
| SKU count by status | Bar chart: In Stock, Low Stock, Out of Stock, Overstock, Slow Mover |
| Top categories by stock value | Table |

**Page 2 — At-Risk Inventory**

What needs attention now.

| Visual | KPIs displayed |
|---|---|
| Out-of-stock SKUs table | SKU, category, days OOS, missed revenue estimate, last receipt date |
| At-risk SKUs (<14 days supply) | SKU, days of supply, recent sales velocity, suggested reorder qty |
| Overstock SKUs (>90 days supply) | SKU, current stock, value, days of supply |
| Slow-moving SKUs | SKU, last sale date, current stock, capital tied up |
| Action priority view | Combined ranked list: highest revenue impact first |

**Page 3 — Velocity**

How fast things move.

| Visual | KPIs displayed |
|---|---|
| Inventory turnover by category | Inventory Turnover, last 12 months annualized |
| Fastest movers — top 20 SKUs | Quantity sold, turn rate |
| Slowest movers — top 20 SKUs | Quantity sold, weeks since last sale |
| Sell-through rate by category | Sell-Through Rate, last 60 days |
| Category velocity quadrant | Bubble chart: turnover × revenue contribution × SKU count |

**Page 4 — Movements**

Inflows and outflows.

| Visual | KPIs displayed |
|---|---|
| Daily inventory movements | Receipts vs. Sales vs. Adjustments, stacked area |
| Movements by type, last 30 days | Bar chart |
| Adjustment audit | Detail table for inventory adjustments (with reasons) |
| Net inventory change by week | Bar chart with positive/negative coloring |
| Movements by category | Table with monthly receipts and sales |

**Page 5 — SKU Detail (drill-through target)**

Single-SKU deep-dive page reached only by drill-through.

| Visual | KPIs displayed |
|---|---|
| SKU header card | Product name, image, category, current stock, current price |
| Stock history, 180 days | Daily quantity_on_hand line chart |
| Sales velocity history | Daily units sold, 90 days |
| Order detail | Recent orders containing this SKU |
| Movement audit | All inventory movements for this SKU, 90 days |

### Drill-through patterns

Inventory has the richest drill-through pattern in the pack:

- **From any SKU appearing on Pages 1–4** → Page 5 (SKU Detail) filtered to that SKU
- **From Page 2 "Out of Stock"** → Page 5 + Sales dashboard Page 4 (Products) filtered to show revenue impact
- **From Page 3 "Slowest Movers"** → Page 5 + Inventory turnover history
- **From Page 1 KPI "Slow-Moving SKU Count"** → Page 2 (At-Risk view, filtered to slow movers)

### Slicers and global filters

- Global: as-of date (default: today)
- Pages 1–4: category multi-select, location filter
- Page 5: SKU (only set via drill-through; not user-selectable directly)

---

## 10.7 Connection model

All three dashboards connect to Snowflake via the **dbt Semantic Layer** (Section 7), not directly to mart tables. This is a deliberate architectural choice with consequences.

### How the connection works

```
Power BI Desktop / Service
       ↓
dbt Semantic Layer GraphQL API
       ↓
Snowflake (executes generated SQL)
       ↓
ANALYTICS_RETAIL.MART_* tables
```

### Why semantic layer, not direct SQL

| If we connected directly to Snowflake tables | With Semantic Layer (chosen) |
|---|---|
| Power BI would write its own DAX measures | Metrics defined once in YAML, consumed identically |
| Refund Rate could differ between dashboards | Single source of truth |
| Adding a new client = redoing DAX | New client = same dashboards, no DAX changes |
| AI assistant would compute differently than Power BI | Both consume the same Semantic Layer |
| Embedded analytics would re-implement metrics | Same metric reused everywhere |

### Connection details

| Setting | Value |
|---|---|
| Connector | dbt Semantic Layer connector (Power BI Pro plan or higher) |
| Authentication | OAuth via dbt Cloud (recommended) or Personal Access Token |
| Account role | `RETAIL_BI_READER` (Section 8.6) |
| Warehouse | `WH_BI` (Section 2.5), auto-suspend 60s |
| Caching | Power BI dataset caching enabled, refresh daily at 6 AM client time |
| Direct Query mode | Available but not default; default is Import for performance |

### Important: dbt Cloud requirement for the Semantic Layer API

The dbt Semantic Layer **GraphQL API** that Power BI connects to is available only via **dbt Cloud Team or Enterprise** plans. Although ADR-001 chose dbt Core as the transformation framework (and the pack's models run on dbt Core), exposing the Semantic Layer to Power BI requires running on dbt Cloud at the API layer.

Two practical paths for clients:

1. **dbt Cloud (recommended for production)** — clients run their dbt project on dbt Cloud. Authoring stays in Git; runtime uses dbt Cloud. The Semantic Layer API is available; Power BI connects directly. Additional cost: dbt Cloud Team tier (~$100/seat/month at time of writing).

2. **dbt Core fallback (open-source path)** — clients running dbt Core without dbt Cloud connect Power BI directly to Snowflake mart tables. Metric formulas live in dbt models that materialize to mart tables; Power BI queries those. This loses the single-source-of-truth benefit (Power BI computes its own DAX measures for some metrics), but works without dbt Cloud.

This trade-off is **documented honestly** in the implementation playbook so clients can choose. The pack's MetricFlow YAML is authored once and consumable either way — Path 1 via the API, Path 2 via materialized views. The decision is formalized in [ADR-004](../07_decisions/ADR-004-dbt-core-vs-cloud-semantic-layer.md).

### Caveats

- The dbt Semantic Layer connector for Power BI is currently in preview at time of writing. The pack pins compatible versions and ships with fallback connection settings via Power BI's direct Snowflake connector if the Semantic Layer connector encounters issues.
- Clients without Power BI Pro can use the fallback connection but lose the metric-consistency benefit.
- Some advanced Power BI features (Q&A natural language, certain visual types) require Import mode rather than DirectQuery — the pack defaults to Import.

---

## 10.8 Refresh and caching

Default refresh strategy:

| Layer | Refresh time | Cost / load |
|---|---|---|
| dbt Cloud pipeline | 3:00 AM client time (Section 2 §2.6 daily schedule) | Snowflake compute |
| Power BI dataset | 6:00 AM client time (after dbt completes) | Power BI gateway |
| Dashboard cache | Auto-warmed on first morning login | Power BI cache |

**Why 3-hour gap between dbt and Power BI:** Allows dbt pipeline failures to be caught and re-run before Power BI tries to read stale or partial data.

### Refresh failure handling

If Power BI refresh fails:

- Cached data from prior day remains queryable (no blank dashboards)
- Failure alert routes to client's data ops Slack channel (Section 8.8)
- Auto-retry once after 30 minutes; if second attempt fails, manual investigation needed

### Real-time data option

For clients needing same-day data: switch the connection to DirectQuery on selected pages. This trades performance for freshness — queries hit Snowflake live instead of cached extracts. Default is Import; DirectQuery available as a per-page override.

---

## 10.9 Theming and visual consistency

A coherent visual identity matters. Three dashboards that look different from each other erode trust.

### Theme components

Every dashboard ships with:

- **Color palette** — primary, secondary, accent, semantic (green = good, red = bad, amber = warning)
- **Typography** — single font family, sizes 11/13/16/22 for body, label, header, KPI value
- **Spacing system** — 8px grid, consistent padding
- **KPI card design** — single shared card visual reused across all dashboards
- **Chart styling** — gridlines, axis labels, legend placement standardized

### Pack default theme

| Element | Value |
|---|---|
| Primary | Spark blue (`#2563EB`) |
| Secondary | Slate gray (`#475569`) |
| Accent | Teal (`#14B8A6`) |
| Positive / good | Green (`#10B981`) |
| Negative / bad | Red (`#EF4444`) |
| Warning | Amber (`#F59E0B`) |
| Background | Off-white (`#FAFAFA`) |
| Text primary | Near-black (`#0F172A`) |
| Text secondary | Slate-600 (`#475569`) |
| Font | Inter (free, web-safe) |

Themes ship as Power BI `.json` theme files in `04_dashboards/themes/`. The pack default theme is "Spark Default." A "client-branded" theme template is also shipped — clients populate it with their own brand colors via the `client_brand.json` config.

### Visual rules enforced

- **No 3D charts.** Ever.
- **No pie charts with more than 5 slices.** Use bar charts for 6+ categories.
- **Color encoding is consistent.** Channels always use the same color across all dashboards.
- **All numeric values formatted.** Currency uses client's reporting currency symbol; large numbers use K/M abbreviation; percentages show one decimal place.
- **All charts have accessible titles.** No "chart 1" or "untitled."
- **Time-series charts always show ≥7 data points.** Single-bar comparisons are forbidden.

These rules are documented in a Power BI style guide that ships with the pack (`04_dashboards/STYLE_GUIDE.md`).

---

## 10.10 Performance budgets

Slow dashboards kill adoption. Targets:

| Action | Budget | Actual on Medium tier demo data |
|---|---|---|
| Dashboard initial load | < 5 seconds | ~3 seconds |
| Page navigation (cached) | < 1 second | <500ms |
| Page navigation (uncached) | < 4 seconds | ~2.5 seconds |
| Slicer change | < 2 seconds | ~1 second |
| Drill-through | < 3 seconds | ~2 seconds |
| Full dataset refresh | < 30 minutes | ~12 minutes |

Performance is measured during CI on Medium tier demo data; regressions fail the build.

### Performance optimizations applied

- **Aggregations in marts.** Mart tables pre-aggregate at the grains dashboards need (daily, monthly). Power BI rarely computes aggregates at query time.
- **Star schema in the dataset.** Power BI's storage engine performs best on a clean star — single fact table per page where possible, dimensions joined by surrogate key.
- **Calculated columns avoided.** Calculations live in dbt models, not in Power BI's calculated columns (slower at query time).
- **Visual count per page.** No more than 8 visuals per page; pages with more get split.
- **Cardinality reduction.** High-cardinality dimensions (customer-grain) are not used as direct slicers; instead, segments and bucketed views.

---

## 10.11 Filtering and slicer architecture

Power BI filtering can become a tangle. The pack enforces consistent patterns.

### Three filter scopes

| Scope | Where applied | Example |
|---|---|---|
| **Page-level** | Affects all visuals on the page | Date range, category |
| **Visual-level** | Single visual only | "Top 10" filter on a bar chart |
| **Report-level (global)** | Every page in the dashboard | Reporting timezone, currency |

### Default behavior

- **Date slicer** appears on every page; persists across navigation
- **Category / channel** slicers appear per page; do NOT persist
- **Bookmarks** let users save filter combinations for quick recall

### Filter naming

User-facing filter names use plain language, not column names:

| Slicer name shown | Underlying column |
|---|---|
| "Date range" | `dim_date.date_actual` |
| "Channel" | `dim_channel.channel_name` |
| "Product category" | `dim_product.category` |
| "Country" | `dim_geography.country_name` |
| "Customer segment" | `dim_customer.customer_segment` |

### What does NOT slice

Some dimensions deliberately don't appear as user slicers:

- **`customer_id` / `customer_sk`** — too high cardinality; available only via drill-through
- **`order_id`** — same reason
- **Date below `day` grain** — hourly slicing not supported in v1

These restrictions are documented in dashboard tooltips.

---

## 10.12 PII and access in dashboards

Per Section 8.6, dashboards connect via `RETAIL_BI_READER` which sees **only hashed PII**. Users see:

- Customer counts, segment names, country codes — visible
- Customer email, phone, full name — hashed
- Order detail tied to specific customer — hashed customer_id, no PII

For roles needing PII (customer service looking up an individual customer):

- Separate `customer_lookup` page exists, connected with `RETAIL_PII_VIEWER` role
- The page is hidden by default; only granted users see it
- All page accesses are logged via Snowflake `ACCESS_HISTORY`

This is the dashboard side of the access pattern defined in Section 8.5 — the architecture guarantees that an executive cannot accidentally surface PII while showing dashboards to a partner.

---

## 10.13 The cross-dashboard navigation

Dashboards link to each other where it makes business sense:

| From | Click target | To |
|---|---|---|
| Executive Summary → Page 4 "Slow-moving SKUs" | Slow-Moving SKU Count card | Inventory Health → Page 2 (At-Risk) |
| Executive Summary → Page 3 "Channel scorecard" | Channel revenue row | Customer 360 → Page 3 (CAC by channel) |
| Customer 360 → Page 3 "ROAS by channel" | Channel ROAS row | Executive Summary → Page 3 (Channel revenue trends) |
| Customer 360 → Page 4 "At-risk customers" | Customer count card | Customer lookup page (PII-protected) |
| Inventory Health → Page 2 "Missed revenue" | Missed revenue per SKU | Executive Summary → Page 5 (Refunds & Returns) |

Cross-dashboard navigation requires that all three dashboard `.pbix` files are in the same Power BI workspace. The pack ships installation instructions to ensure this.

---

## 10.14 Distribution

How dashboards ship with the pack.

### What clients receive

| File | Purpose |
|---|---|
| `04_dashboards/executive/SparkRetail_Executive.pbix` | Executive Summary dashboard |
| `04_dashboards/customer_360/SparkRetail_Customer360.pbix` | Customer 360 dashboard |
| `04_dashboards/inventory_health/SparkRetail_InventoryHealth.pbix` | Inventory Health dashboard |
| `04_dashboards/themes/SparkDefault.json` | Default Power BI theme |
| `04_dashboards/themes/client_brand.json` | Customizable theme template |
| `04_dashboards/STYLE_GUIDE.md` | Visual style rules |
| `04_dashboards/INSTALLATION.md` | Setup walkthrough |
| `04_dashboards/USER_GUIDE.md` | End-user navigation guide |

### Distribution model

Per Section 10.2: **all dashboards are proprietary**. They ship only with the paid (`spark_retail_pack_pro`) tier. The open-source repo references the dashboards but does not include the `.pbix` files.

### Installation

A client implementation engagement includes dashboard setup:

1. Engineer installs the dbt Semantic Layer connector in client's Power BI environment
2. Authentication configured (OAuth or PAT)
3. `.pbix` files uploaded to the client's Power BI workspace
4. Refresh schedule configured (default: daily 6 AM client time)
5. Theme customized with client branding (~30 min)
6. User access roles configured (Section 8.6 mapping)
7. Cross-dashboard navigation verified
8. User training session (~1 hour, included in implementation)

Total dashboard setup time: typically half a day during a 4–6 week implementation.

### Versioning

Dashboards version with the pack (Section 4 Part 3 §4.38). When the underlying canonical model has a major version bump, dashboards are rebuilt and re-shipped. Minor version bumps (new columns) typically don't require dashboard updates unless the new column is a new slicer; patch versions never require updates.

---

## 10.15 What's not in v1

Honest scope statement.

| Feature | Why deferred |
|---|---|
| Mobile-optimized dashboards | Power BI Mobile works but layouts aren't optimized; v2 |
| Custom AI assistant integration | The AI assistant (Section 7.14) is a v2 feature |
| Embedded analytics for end-clients (white-label) | Mentioned as a future capability in Sections 2.2 and 7.14; full embedded analytics is v2 |
| Real-time / streaming dashboards | Batch only in v1 |
| Marketing Attribution dashboard | Module deferred (Section 3.8) |
| Customer Service / Support dashboard | Connectors deferred |
| Fulfillment dashboard | Module deferred |
| Subscription / recurring revenue dashboard | Module deferred |
| Multi-currency dashboard views | All amounts in reporting currency; native multi-currency is v2 |
| Localized dashboards (non-English) | English only in v1 |
| Looker / Tableau / Metabase equivalents | Power BI only in v1 per ADR-001 |

Each of these is on the v2 roadmap, prioritized by client demand signals during v1 deployment.

---

## 10.16 Common customizations clients make

Even pre-built dashboards are customized during implementation. Typical patterns:

### Customization 1 — Adding the client's logo and brand colors

A 30-minute task. Edit `client_brand.json`, save, and reapply theme.

### Customization 2 — Renaming KPIs to match the client's vocabulary

Some clients call "GMV" "Total Sales"; some call "Net Revenue" "Realized Revenue." The pack supports per-deployment label overrides in `04_dashboards/labels_override.json`:

```json
{
  "gmv": "Total Sales",
  "net_revenue": "Realized Revenue",
  "average_order_value": "Avg Basket Size"
}
```

Applies across all three dashboards consistently.

### Customization 3 — Adding client-specific pages

Some clients have a specific weekly review they want as a dashboard. The pack supports adding custom pages without modifying the shipped pages. Custom pages live in `04_dashboards/custom_pages/` and are merged on Power BI publish.

### Customization 4 — Removing pages

Clients without a relevant data source (e.g., no Klaviyo = no email engagement) can hide the email page. Pages are not deleted (preserves upgrade path); they're hidden.

### Customization 5 — Adjusting refresh frequency

Default is daily 6 AM. Some clients want hourly during business hours, twice daily, etc. Configurable via Power BI Service settings.

### What clients should NOT customize

Three things are off-limits for client-side editing without breaking the upgrade path:

1. **Metric definitions** — these live in the semantic layer YAML, not in Power BI. Editing DAX would create divergence.
2. **Filter relationships** — the data model relationships are set by the semantic layer; overriding in Power BI breaks consistency.
3. **Visual types on shipped pages** — replacing a chart with a different chart type breaks the dashboard's design language.

For these, clients work with their Spark Analytics consultant to make changes properly (e.g., add a new metric to the semantic layer rather than computing it in DAX).

---

## 10.17 Summary

Three Power BI dashboards (Executive Summary, Customer 360, Inventory Health), five pages each, totaling 15 pages of designed analytics that surface every KPI from Section 5 to actual users.

Key design decisions:

- **All three dashboards are proprietary** — the visual IP is where commercial value concentrates
- **Connection via Semantic Layer**, not direct SQL — guarantees metric consistency across Power BI, the AI assistant, and any other consumer
- **Three-layer filter architecture** (page, visual, global) keeps Power BI filter complexity manageable
- **PII-protected by default** — dashboards see only hashed PII unless the user has the PII viewer role
- **Performance budgets enforced** in CI — sub-5-second dashboard loads, sub-2-second slicer changes
- **Cross-dashboard navigation** lets users jump from executive view to inventory detail without context loss
- **Customization is bounded** — clients can rebrand, rename, add pages; they cannot modify metric formulas in Power BI (the semantic layer owns that)

The pack now has:

- A canonical data model (Section 4)
- 25 KPIs defined (Section 5)
- Five connectors specified (Section 6)
- A semantic layer encoding the KPIs (Section 7)
- A governance baseline (Section 8)
- A realistic demo dataset (Section 9)
- Three production-grade dashboards (Section 10)

What remains is the commercial framing — Section 11 consolidates the open-source vs. proprietary split that's been touched on in every prior section. Section 12 sequences the build into a phased roadmap with effort estimates.

---

**Previous:** [Section 9: Demo Data Design](./09_demo_data_design.md)
**Next:** [Section 11: Open-Source vs. Pro Split](./11_open_source_vs_pro_split.md)
