# Section 9: Demo Data Design

> **Document status:** Draft v1
> **Audience:** Sales and demo team, implementation engineers, QA/testing team, contributors
> **Purpose:** Define the synthetic demo dataset that ships with the Spark Retail Pack — its fictional client, scale, story arcs, generation approach, validation, and use in sales demos and CI testing.

---

## 9.1 Why this section matters

A productized data warehouse without a demo dataset is unsellable. Prospects need to see the dashboards populated with realistic numbers, the AI assistant answering questions about a believable business, and the connectors working without first signing a contract. Section 9 defines the data that powers all of that.

The demo dataset is **simultaneously** four things:

1. **A sales asset** — populates dashboards in a demo environment that prospects can explore
2. **A development fixture** — engineers build and test against it locally
3. **A CI test bed** — every dbt build runs against demo data and validates KPI values against expected results (per Section 7 §7.15)
4. **An onboarding aid** — new clients use it to learn the pack before pointing it at their own data

Designing one dataset to serve all four uses is the constraint. It must be:

- **Realistic enough** to be convincing in sales demos
- **Stable enough** to support deterministic CI tests
- **Small enough** to load fast (under 15 minutes on a default Snowflake warehouse)
- **Large enough** to exercise real-world patterns (seasonality, cohorts, anomalies)
- **Story-driven** — generic random data is forgettable; data with narrative arcs sticks

---

## 9.2 Design principles

Five principles shape every decision in this section.

1. **Realistic, not random.** Generic random data ("100,000 orders with uniform distribution") is unconvincing and tells no story. The pack's data follows realistic distributions — weekly seasonality, growth trends, category-level price variation, plausible customer behavior.

2. **One company, one story.** A single fictional retailer ("Northwind Co.") with a coherent business model, product catalog, customer base, and 12-month history. Multiple disjoint scenarios spread across the dataset weaken every individual demo.

3. **Narrative arcs are embedded.** Five business events occur during the 12-month period (§9.5) that show up as identifiable patterns in the dashboards: a Black Friday spike, an inventory crisis, a churn event, a viral marketing moment, a product line failure. Sales demos walk through these stories.

4. **Deterministic generation.** The same seed produces the same data byte-for-byte. This makes CI tests reliable and lets sales teams demo against an identical environment every time.

5. **Multi-scale.** Three sizes ship — Small (development), Medium (default demo), Large (load testing). Same story, different volumes.

---

## 9.3 The fictional client: Northwind Co.

A complete fictional company designed to be **a plausible target client**, not a fantasy retailer.

### Company profile

| Attribute | Value |
|---|---|
| Name | Northwind Co. |
| Industry | Direct-to-consumer apparel and accessories |
| Founded | 2022 |
| Headquarters | Portland, Oregon (US) |
| Annual revenue (GMV) | ~$24M (2026 run-rate) |
| Annual order volume | ~120K orders |
| Active customer base | ~85K customers (90-day) |
| SKU count | ~2,400 |
| Markets | US (primary, 70%), Canada (15%), UK (10%), Australia (5%) |
| Currencies | USD (reporting), CAD, GBP, AUD |
| Channels | Online store (primary), Instagram Shopping, Facebook Shop, two retail pop-ups |
| Team size | ~80 employees |

This profile matches the **center of the target client segment** defined in Section 1.3 ($5M–$200M GMV mid-market D2C). A prospect at $30M GMV looking at the demo can imagine themselves immediately; a prospect at $5M can see where they're heading; a prospect at $200M can see how the pack scales.

### Product catalog

The catalog is plausibly varied for an apparel retailer:

| Category | Subcategory | SKU count | Price range | Notes |
|---|---|---|---|---|
| Outerwear | Jackets | 180 | $89–$320 | Hero category, seasonal |
| Outerwear | Coats | 90 | $180–$540 | Premium tier |
| Tops | T-shirts | 380 | $28–$58 | Volume category |
| Tops | Sweaters | 220 | $68–$148 | Mid-tier |
| Tops | Shirts | 180 | $48–$98 | |
| Bottoms | Jeans | 240 | $78–$148 | |
| Bottoms | Pants | 180 | $58–$118 | |
| Bottoms | Shorts | 90 | $38–$68 | Strongly seasonal |
| Accessories | Bags | 120 | $48–$280 | |
| Accessories | Hats | 80 | $28–$48 | |
| Accessories | Belts | 60 | $38–$78 | |
| Accessories | Socks | 90 | $12–$22 | Volume add-on |
| Footwear | Sneakers | 180 | $98–$220 | |
| Footwear | Boots | 90 | $148–$320 | Seasonal |
| Footwear | Sandals | 60 | $58–$88 | Strongly seasonal |
| Limited Editions | Various | 160 | $48–$420 | Drives the "viral moment" scenario (§9.5.4) |

~2,400 total SKUs, spread across realistic categories with plausible price ladders.

### Customer base

Customer geography and segment distribution:

| Segment | Share | Behavior |
|---|---|---|
| One-time buyer | 62% | Single purchase, never returned |
| Casual repeat | 25% | 2–4 orders, average gap 90+ days |
| Loyal customer | 10% | 5+ orders, average gap <60 days |
| VIP | 3% | 10+ orders, high AOV, frequent purchases |

This 62/25/10/3 distribution is consistent with typical D2C retail patterns — a long tail of one-time buyers, a thin VIP cohort. Actual benchmarks vary by category and price point; this distribution is plausible for mid-market apparel.

### Marketing footprint

Active channels with realistic spend distribution:

| Channel | Annual spend | Customers acquired | Notes |
|---|---|---|---|
| Meta (Facebook + Instagram) | $1.8M | ~28K | Primary acquisition channel |
| Google Ads | $0.9M | ~14K | (Generated, even though no Google Ads connector in v1 — flagged below) |
| Email (Klaviyo) | $60K (platform) | ~8K (reactivated) | Retention-focused |
| Organic search | $0 | ~16K | SEO foothold |
| Referral | $80K | ~6K | Influencer partnerships |
| Direct | $0 | ~13K | Brand awareness conversions |

**Note on Google Ads:** The demo includes Google Ads spend in `fact_marketing_spend` for narrative completeness, but the v1 connector set does not include Google Ads (per Section 6.3). The data is generated as if from a hypothetical Google Ads connector and uses `_source_system = 'generated'`. This is flagged in the demo notes for honesty; v2 will replace with real Google Ads ingestion.

---

## 9.4 Data volume and shape

Three volume tiers ship. Same Northwind Co. story; different fidelities.

### Size tiers

| Tier | Use case | Orders | Customers | SKUs | Total rows (approx.) | Snowflake load time |
|---|---|---|---|---|---|---|
| **Small** | Local dev, unit tests | 5,000 | 3,500 | 600 | 1.2M | <2 min |
| **Medium** | Default demo, CI | 120,000 | 85,000 | 2,400 | 28M | <8 min |
| **Large** | Load testing, enterprise demo | 600,000 | 420,000 | 2,400 | 140M | <25 min |

All tiers cover the same 12-month period (Jan 2026 – Dec 2026); volume differs by transaction rate, not by time span.

### Time coverage

The demo data spans **January 1, 2026 through December 31, 2026** in all tiers. The "current date" for demo purposes is January 5, 2027 — letting users browse a full completed year while also demonstrating live recency features (yesterday, last week, MTD with January 2027 data).

### Row volume by fact (Medium tier)

| Fact | Row count | Notes |
|---|---|---|
| `fact_orders` | ~120,000 | One per completed order |
| `fact_order_lines` | ~340,000 | Avg ~2.8 lines per order |
| `fact_refunds` | ~4,800 | ~4% refund rate |
| `fact_marketing_spend` | ~21,000 | Daily × ~57 active campaigns |
| `fact_web_sessions` | ~7.8M | ~21K/day average |
| `fact_email_engagement` | ~14M | Klaviyo events |
| `fact_customer_state_daily` | ~22M | 85K customers × 261 active days |
| `fact_inventory_snapshot` | ~876K | 2,400 SKUs × 365 days × 1 location |
| `fact_inventory_movements` | ~520,000 | Receipts + sales + adjustments |

Total: ~28M rows. Snowflake handles this comfortably on an XSmall warehouse for demo querying.

**Note on scale vs. Section 4.30:** The capacity-planning profile in Section 4 Part 2 §4.30 (~210M rows total) describes a larger reference client (500K customers, 10K SKUs, 3 locations). Northwind Co. is deliberately smaller — single location, narrower SKU range — to keep demo load times under 8 minutes while still exercising every metric. The Large tier (§9.4) approaches the §4.30 profile for enterprise demos that need to show realistic load behavior.

---

## 9.5 The five embedded story arcs

The demo data has five narrative events embedded over the 12-month period. Each is identifiable in the dashboards without explanation. Each maps to a specific KPI behavior change the demo can walk through.

### Story 1 — Black Friday spike (November 28–December 1, 2026)

**The narrative:** Northwind's biggest sales weekend of the year. Four days of promotional activity drive revenue to roughly 8× normal daily volume, with cascading effects on inventory, customer acquisition, and refunds.

**Observable in dashboards:**

- **Executive Summary:** Daily GMV spike from ~$66K average to ~$540K peak (Black Friday). November total revenue ~$3.2M (vs. ~$1.8M typical month).
- **Customer 360:** Spike in new customers (Nov 28: ~1,400 new vs. ~70/day typical). Acquisition cost drops temporarily (organic and referral grow disproportionately).
- **Inventory Health:** ~80 SKUs hit stockout by Cyber Monday. Sell-through on Limited Editions reaches 95% within 4 days. Inventory value drops noticeably across November.
- **Refund pattern:** Refund volume spikes 6–8 weeks later (mid-January 2027), tail of post-holiday returns. Demo runs in early Jan so this is just beginning to surface.

**KPIs impacted:** GMV, Order Count, AOV (slightly lower due to discounting), New Customers, CAC (lower), ROAS (higher), Stockout Rate, Sell-Through Rate.

### Story 2 — Inventory crisis on top SKU (April 8–April 25, 2026)

**The narrative:** Northwind's best-selling "Heritage Denim Jacket" (SKU `HJ-001-MED-BLU`) goes out of stock at the worst possible time — a spring fashion week mention drives unexpected demand, and a delayed supplier shipment leaves shelves empty for 17 days. Lost revenue estimated at $180K.

**Observable in dashboards:**

- **Inventory Health:** `HJ-001-MED-BLU` goes to zero stock April 8. Stockout flag fires. Days of supply drops to 0. The Inventory at Risk dashboard surfaces this SKU prominently.
- **Sales Analytics:** Dip in Outerwear/Jackets category revenue from April 9 onward. Recovery on April 26 after restock.
- **Customer 360:** Customer service ticket spike (not in v1 data, mentioned in scenario notes). Email engagement on "back in stock" notifications spikes April 26.

**KPIs impacted:** Stockout Rate, Days of Supply, Sell-Through Rate, Revenue by Category (Outerwear), Inventory at Risk count.

### Story 3 — Churn event (June–August 2026)

**The narrative:** A pricing change on the Sweaters subcategory in early June (Northwind raised prices ~12% across the line) triggers customer dissatisfaction. Repeat purchase rate declines through summer; reviews mention sticker shock; email engagement drops on Sweater-themed campaigns.

**Observable in dashboards:**

- **Customer 360:** Repeat Purchase Rate drops from ~28% in May to ~22% in July, before recovering to ~26% by September.
- **Customer 360 cohorts:** The June 2026 acquisition cohort underperforms — lower repeat rate, lower LTV.
- **Sales Analytics:** Sweater category revenue flat despite the price increase (meaning volume dropped to offset).
- **Email Engagement:** Click-through on sweater campaigns drops from ~4.2% to ~2.8% in July.

**KPIs impacted:** Repeat Purchase Rate, LTV (cohort-level), Email Engagement Rate, AOV (slightly up — fewer but higher-value purchases), Revenue by Category.

### Story 4 — Viral moment (September 14–28, 2026)

**The narrative:** A mid-tier influencer (~280K followers) posts an unboxing video featuring Northwind's "Cargo Field Pants" on September 14. The post goes viral. New customer acquisition spikes from ~70/day to ~600/day for two weeks. ROAS on the September Meta campaign jumps because attribution captures the surge. The product sells out by September 22.

**Observable in dashboards:**

- **Customer 360:** New customer count for September 2026 is ~7,400 vs. ~2,500 monthly typical. Acquisition channel breakdown shows "Referral" and "Direct" (untracked viral spillover) growing disproportionately.
- **Sales Analytics:** Revenue spike concentrated in Bottoms/Pants subcategory. Cargo Field Pants becomes #1 SKU for the period.
- **Inventory Health:** Cargo Field Pants stockout on September 22; back in stock October 8.
- **Customer 360 (CAC):** Reported CAC for September drops because the warehouse attributes more orders to existing marketing spend.

**KPIs impacted:** New Customers, CAC by Channel, ROAS, Revenue by Product, Stockout Rate (Cargo Field Pants).

### Story 5 — Failed product line (March–May 2026)

**The narrative:** Northwind launches a "Resort Wear" capsule on March 1 — 18 SKUs targeting Spring Break travelers. The line underperforms badly. By April 15, only ~22% of inventory has sold. Slow-mover flags fire. By May 30, the line is moved to clearance.

**Observable in dashboards:**

- **Inventory Health:** ~14 of the 18 Resort Wear SKUs flagged as slow-movers by mid-April. Inventory value tied up in the line surfaces in "Inventory at Risk."
- **Sales Analytics:** Resort Wear subcategory revenue is a fraction of expected — visible in the Category Performance view.
- **Sell-Through Rate:** Resort Wear hits 22% at 30 days vs. typical new launches at ~60%.
- **Inventory Health (clearance):** Sharp price discounts in May visible on these SKUs.

**KPIs impacted:** Sell-Through Rate, Slow-Moving SKU Count, Overstock Value, Total Inventory Value.

### Story arc summary

The five stories are spread across the year so a demo can pick any quarter and have something interesting to show:

| Quarter | Primary stories | Demo opportunity |
|---|---|---|
| Q1 (Jan–Mar) | Story 5 launch (March) | "Watch what happens when a product line fails to land" |
| Q2 (Apr–Jun) | Story 2 (April), Story 5 continues, Story 3 begins (June) | "See how the inventory crisis surfaces in real time" |
| Q3 (Jul–Sep) | Story 3 continues, Story 4 (September) | "Here's what a viral moment looks like in the data" |
| Q4 (Oct–Dec) | Story 1 (November) | "How Black Friday cascades through every metric" |

A typical sales demo walks through Story 1 (Black Friday) for executive impact, then Story 4 (viral moment) for marketing teams. Engineering demos focus on Stories 2 and 5 (inventory).

---

## 9.6 Generation approach

The demo data is **generated procedurally** from a small set of configuration files. No hand-curated data, no third-party datasets, no anonymized real client data.

### Why procedural generation

- **Deterministic.** Same seed = same output. Critical for CI.
- **Scalable.** The same generator produces Small, Medium, and Large tiers from the same config.
- **Maintainable.** When the canonical model evolves (new columns, new facts), the generator updates once and regenerates everything.
- **Legal.** No risk of accidentally including real customer data; no privacy concerns; no licensing issues.
- **Story-controllable.** Embedded narratives (§9.5) are programmed in; they appear reliably.

### Tools and approach

| Tool | Purpose |
|---|---|
| **Python 3.11+** | Generator language |
| **Faker** | Realistic-looking names, addresses, emails (with `unique` modifier so the same email doesn't repeat) |
| **NumPy** | Distribution sampling (revenue per order, time gaps, etc.) |
| **Pandas** | Data shaping and CSV/JSON output |
| **Custom story modules** | Each of the 5 stories is a separate Python module that "injects" the narrative into a baseline stream of events |

The generators live in `05_demo_data/generators/`:

```
05_demo_data/
├── README.md
├── config/
│   ├── northwind_company.yml          # Company-level config (name, currency, fiscal year)
│   ├── product_catalog.yml            # All 2,400 SKUs across categories
│   ├── customer_segments.yml          # Segment distribution and behavior
│   └── marketing_calendar.yml         # When campaigns are active
├── generators/
│   ├── generate_customers.py
│   ├── generate_products.py
│   ├── generate_orders.py
│   ├── generate_inventory.py
│   ├── generate_sessions.py
│   ├── generate_email_events.py
│   ├── generate_marketing_spend.py
│   ├── stories/
│   │   ├── story_1_black_friday.py
│   │   ├── story_2_inventory_crisis.py
│   │   ├── story_3_pricing_churn.py
│   │   ├── story_4_viral_moment.py
│   │   └── story_5_resort_wear_flop.py
│   └── main.py                         # Orchestrates the full generation
├── datasets/
│   ├── small/                          # Pre-generated CSVs
│   ├── medium/
│   └── large/
├── loaders/
│   ├── load_to_snowflake_bronze.sql    # Loader scripts
│   └── load_via_fivetran_simulator.py  # Alternative path
└── scenarios/                          # Demo scripts that walk through each story
    ├── black_friday_demo.md
    ├── inventory_crisis_demo.md
    └── ...
```

### The generation pipeline

```
1. Generate baseline events (orders, sessions, etc.)
   following realistic distributions and growth curve
        ↓
2. Apply story overlays — each story modifies the
   baseline stream during its time window
        ↓
3. Derive dependent data — sessions for each order,
   email events for each marketing campaign, refunds
   for a sampled subset of orders
        ↓
4. Generate inventory snapshots — daily, derived from
   movements (receipts + sales) + initial stock
        ↓
5. Generate customer state snapshots — derived from
   order history per customer
        ↓
6. Output to source-system format (Shopify-shaped JSON,
   Stripe-shaped JSON, GA4-shaped events, etc.)
        ↓
7. Pre-load into bronze tables OR ship as CSV/JSON for
   ingestion-tool simulation
```

Each story module operates as a transformation on the baseline event stream. For example, `story_1_black_friday.py` reads the baseline order stream for November 28–December 1, multiplies order volume by configurable factors per day, injects discount codes, and increases the new-customer ratio.

### Determinism

The full generation pipeline accepts a single `seed` parameter. Same seed produces byte-identical output. Default seed for the shipped demo: `42` (Medium tier). Small and Large tiers use seeds `41` and `43` respectively — different volumes but same story shape.

A CI test verifies determinism: regenerate the Medium dataset with seed 42 and compare to the shipped dataset; any difference fails the build.

---

## 9.7 Source-system shape compliance

The generator produces data **in the shape of each source system**, not pre-mapped to the canonical model. This is intentional:

- The demo exercises the staging layer, intermediate layer, and core layer the same way real client data does
- Connector mappings (Section 6) are validated end-to-end on demo data
- Demos can show "raw Shopify-like data on the left, canonical model on the right"

### Output formats per source

| Source | Output format | Example file |
|---|---|---|
| Shopify | JSON files, one per table, matching Shopify API shape | `datasets/medium/shopify/orders.json` |
| Stripe | JSON files, matching Stripe API shape | `datasets/medium/stripe/charges.json` |
| GA4 | JSON/Parquet matching BigQuery export schema | `datasets/medium/ga4/events_2026XXXX.parquet` |
| Meta Ads | JSON matching Meta Marketing API insights | `datasets/medium/meta_ads/daily_insights.json` |
| Klaviyo | JSON matching Klaviyo Events API | `datasets/medium/klaviyo/events.json` |

These can be loaded directly to Snowflake bronze tables via the SQL scripts in `loaders/`, or pushed through Fivetran/Airbyte in test environments via the simulator (which mimics those tools' typical column-naming output).

### Source contract validation

The generator includes a self-test that validates its output against the source contracts defined in Section 6 — every "required source field" per connector. If the generator produces Shopify-shaped data missing a required field, the test fails. This protects against drift between Section 6 and the demo.

---

## 9.8 Statistical realism

Random data is a giveaway. Demo data must follow realistic distributions in five dimensions.

### Realism dimension 1 — Weekly seasonality

D2C retail has strong weekly patterns: weekends generate more orders than weekdays; Mondays are often the lowest day. The generator applies a multiplier per day-of-week:

| Day | Multiplier |
|---|---|
| Monday | 0.85 |
| Tuesday | 0.92 |
| Wednesday | 0.95 |
| Thursday | 1.00 |
| Friday | 1.08 |
| Saturday | 1.18 |
| Sunday | 1.12 |

### Realism dimension 2 — Monthly seasonality

| Month | Demand multiplier | Notes |
|---|---|---|
| January | 0.85 | Post-holiday lull |
| February | 0.78 | Lowest month |
| March | 0.92 | Spring launches |
| April | 0.95 | |
| May | 1.00 | |
| June | 1.02 | |
| July | 0.94 | Summer dip |
| August | 0.96 | Back-to-school start |
| September | 1.08 | Fall launches + viral moment |
| October | 1.05 | |
| November | 1.65 | Black Friday |
| December | 1.40 | Holiday gifting |

The Story 1 (Black Friday) overlay further amplifies November 28 – December 1.

### Realism dimension 3 — Order value distribution

Order values follow a **log-normal distribution**, not uniform. Most orders cluster around $80–$140; a long tail of higher-value orders extends to $800+. The generator samples from log-normal with mean ln(110) and stddev 0.45.

### Realism dimension 4 — Customer behavior

Customers don't all behave the same way. The generator assigns each customer to a segment (per §9.3) and draws subsequent orders from segment-specific distributions:

| Segment | Avg gap between orders | AOV multiplier vs. mean | Lifetime order count |
|---|---|---|---|
| One-time | n/a | 1.0× | 1 |
| Casual repeat | 95 days (high variance) | 1.0× | 2–4 |
| Loyal | 45 days | 1.15× | 5–9 |
| VIP | 22 days | 1.4× | 10–35 |

### Realism dimension 5 — Geographic and channel realism

- 70% US, 15% Canada, 10% UK, 5% Australia (per §9.3)
- Within US: heavier weighting to coastal states (California, New York, Texas, Florida)
- Channel acquisition follows realistic distribution (Meta 38%, organic search 22%, direct 18%, referral 12%, Google 10%, email reactivation in retention not acquisition)

### Anti-patterns explicitly avoided

The generator deliberately does NOT:

- Use real customer names or addresses (Faker generates fictional)
- Use real company names other than Northwind (no "Acme Corp" placeholders)
- Use perfectly round numbers (revenue $1,000,000.00 is suspicious; $1,032,847.50 is realistic)
- Use uniform distributions where real data is skewed
- Generate exact duplicates (every order_id, every customer email is unique)

---

## 9.9 Known KPI values for validation

The demo data has **known correct values** for every KPI in the catalog (Section 5), at every supported time grain. These are documented in `05_demo_data/expected_values.yml` and used by CI to validate that the pack computes correctly.

### How the expected values are derived

The generator computes its own truth as it produces data. As `fact_orders` rows are emitted, the generator increments running totals; as `fact_customer_state_daily` rows are created, the generator tracks unique customers per segment per day. The final tallies are dumped to `expected_values.yml`.

This is **not** "compute the KPI from the demo data and call that the expected value" — that would be circular. The generator computes truth from its own emission stream, independently of the dbt model that later consumes the data.

### Example expected values (Medium tier, 2026 full year)

```yaml
# 05_demo_data/expected_values.yml
year: 2026
tier: medium
seed: 42

metrics:
  sales:
    gmv:
      year: 24_847_320.50
      quarters:
        Q1: 4_982_140.00
        Q2: 5_493_870.00
        Q3: 6_122_540.50
        Q4: 8_248_770.00     # Black Friday boost
      months:
        2026-11: 3_182_640.00
        2026-12: 2_704_350.00
        # ... etc
    net_revenue:
      year: 22_182_405.75
      # ... etc
    order_count:
      year: 119_843
    average_order_value:
      year: 207.39
    revenue_growth_pct:
      2026-11_vs_2026-10: 78.4
    refund_rate:
      year_pct: 4.12
  
  customer:
    active_customers_30d:
      "2026-12-31": 47_281
      "2026-09-15": 62_310     # Viral moment peak
    new_customers:
      year: 84_672
      2026-09: 7_438           # Story 4 spike
    repeat_purchase_rate:
      year_pct: 24.6
      2026-07_pct: 22.1        # Story 3 dip
      2026-09_pct: 26.4
    cac_by_channel:
      year:
        meta: 64.30
        google: 67.10
        referral: 13.40
  
  inventory:
    total_inventory_value:
      "2026-04-08": 2_847_320  # Just before Story 2
      "2026-04-15": 2_653_180  # During Story 2 stockout
    inventory_turnover:
      year: 5.82
    stockout_rate:
      "2026-04-15_pct": 3.4    # Story 2 peak
      "2026-12-01_pct": 8.7    # Story 1 Black Friday aftermath
```

The full file lists exact expected values for all 25 KPIs at multiple grains. ~3,000 expected values total.

### How validation runs

A dbt test (`tests/demo_data_kpi_validation.sql`) reads the expected values and compares to actual computed KPI values:

```yaml
# tests/demo_data/test_gmv_2026_year.yml
- name: demo_gmv_2026_year_matches_expected
  metric: gmv
  filter: "metric_time >= '2026-01-01' AND metric_time <= '2026-12-31'"
  expected: 24_847_320.50
  tolerance: 0.01  # 1 cent
```

If a model change breaks any KPI's expected value, CI fails before merge. This is what makes the demo dataset a regression-prevention asset, not just a sales asset.

### Tolerance and drift

For ratio metrics (AOV, refund rate, etc.), tolerance is set to ±0.5% to accommodate rounding. For absolute counts and amounts, tolerance is 0 (exact match required). Acceptable drift is documented per metric.

---

## 9.10 Distribution and deployment

### How clients receive the demo data

Three delivery options:

1. **Pre-loaded Snowflake shared database.** Spark maintains a public Snowflake share (`SPARK_RETAIL_DEMO`) that clients can clone into their account in seconds via zero-copy cloning. This is the fastest path; recommended for evaluation.

2. **Downloadable CSV/JSON bundles.** Clients with no Snowflake account, or who want to test their own ingestion tool, download `datasets/medium/*.zip` (~250MB compressed). They load it through their preferred path (Fivetran, Airbyte, custom).

3. **Re-generation.** Clients with the open-source repo can `python generators/main.py --tier medium --seed 42` to recreate the dataset locally. Useful for offline demos and customization.

The proprietary version of the demo includes additional scenarios (the AI-ready metadata, the embedded analytics tenant simulation) — those don't ship with the OSS download.

### Refresh cadence

The shipped demo dataset is refreshed when:

- The canonical model changes (new columns, new facts, schema migrations) — major refresh
- A new story scenario is added — minor refresh
- A bug is fixed in the generator — patch refresh

Versioning follows the pack's semantic versioning (Section 4 Part 3 §4.38). The demo dataset version is declared in `expected_values.yml`.

### Sales demo environments

For prospect-facing demos, Spark maintains a hosted Snowflake account loaded with the Medium tier dataset, with the full Power BI dashboard pack connected. Prospects can:

- View dashboards live
- Run their own questions through the AI assistant
- Inspect the underlying dbt models if they're technical
- See the lineage in dbt docs

The hosted environment refreshes nightly; demo recordings of each story arc are captured weekly to ensure consistency in sales materials.

---

## 9.11 Limitations and known issues

Honest scope statement.

### What the demo doesn't simulate well

| Limitation | Workaround |
|---|---|
| **Real customer service workload** | No support ticket data; refund reasons are categorical, not narrative |
| **Real product photography / descriptions** | Product names/categories are realistic but no actual content |
| **Real social media engagement nuance** | Viral moment is modeled as a spike, not a full social timeline |
| **Subscription / recurring orders** | Not in v1 — Northwind is pure one-time-purchase D2C |
| **B2B / wholesale orders** | Northwind is pure D2C; B2B requires a separate dataset (v2) |
| **Multi-warehouse fulfillment** | Single fulfillment location in v1 (Portland warehouse) |
| **Localization** | English-only; doesn't exercise multi-language analytics |
| **GDPR / consent variance** | All customers have standard consent state; doesn't exercise edge cases |

### Honest acknowledgment of synthetic-data tells

A trained eye can spot synthetic data:

- Customer names follow Faker's distribution (some unusual combinations)
- Addresses are real-but-randomized; mailing them would fail
- Email patterns are diverse but follow common providers
- Phone numbers are E.164-valid but won't reach anyone

This is fine for demos — prospects expect synthetic data — but it's important to be honest. The pack ships a disclaimer in the demo dashboards: "This is synthetic data representing 'Northwind Co.' — a fictional retailer designed to showcase Spark Retail Pack capabilities."

### What v2 will add

| v2 addition | Why |
|---|---|
| Customer service ticket data | Once Zendesk/Gorgias connectors ship |
| Subscription order patterns | Once subscription module ships |
| Multi-location fulfillment | Adds complexity to inventory scenarios |
| B2B wholesale dataset variant | "Northwind Wholesale Co." — different fact patterns |
| AI-ready metadata in demo | Already implicit; v2 makes the AI demo experience richer |

---

## 9.12 Demo scripts and sales scenarios

For each of the 5 stories (§9.5), a structured demo script ships in `05_demo_data/scenarios/`. These are the sales team's playbooks.

### Anatomy of a demo script

Each script has:

| Section | Content |
|---|---|
| **Audience** | Who this demo is for (CEO, marketing lead, ops lead) |
| **Setup** | Which dashboard, which date range to open |
| **The hook** | One sentence to set up the story ("Watch what happens to Northwind during Black Friday weekend") |
| **The walkthrough** | Step-by-step screens to navigate, with exact KPI values to call out |
| **The "aha" moment** | The single insight that lands the demo |
| **Questions to expect** | Common prospect questions with prepared answers |
| **The follow-up ask** | What to propose next (POC, technical deep-dive, etc.) |

### Example: Black Friday demo script (excerpt)

```markdown
# Black Friday Demo Script

**Audience:** CEO, Head of Finance
**Duration:** 8 minutes
**Open:** Executive Summary dashboard, date range = November 1 – December 15, 2026

## The Hook
"Most data teams can tell you what happened during Black Friday. 
The question is: can they tell you what's about to happen next? 
Let's look at how Northwind's analytics surfaced the upcoming refund 
spike and the inventory shortfall — three weeks before the CFO asked."

## Walkthrough
1. **Daily Revenue chart, Nov 1–30**
   - Call out the visible spike Nov 28–Dec 1
   - Peak day: November 29, $543K (8.2× November average)
   
2. **Drill into Cyber Monday (December 1) order detail**
   - Show order count: 3,847 orders that day
   - Average Order Value drops to $98 vs. monthly avg of $207 (discount-driven)
   
3. **Switch to Customer 360 → Acquisition**
   - New customers: 1,402 on November 29 alone
   - CAC drops to $42 vs. typical $73 (lower competition, higher organic share)
   
4. **Switch to Inventory Health**
   - Show "Out of Stock" dashboard for December 2
   - 78 SKUs at zero stock — Limited Editions hit hardest
   - Inventory at Risk view: $340K of stock dropped below 14 days of supply
   
5. **Back to Executive Summary → Refunds preview**
   - January 2027 already showing 4× refund spike forming
   - "This is the kind of forward visibility that lets the finance team 
     accrue correctly before quarter-end"

## The "Aha" Moment
"The dashboards didn't compute these in real time during Black Friday — 
they computed them while you were drinking coffee on December 6. 
The semantic layer does the work; you get the answers."

## Questions to Expect
- "How quickly could we get this running on our data?" → 4–6 weeks
- "Does it work with our [non-Shopify] storefront?" → Connector roadmap discussion
- "What about [specific KPI we don't yet support]?" → Section 5.13 deferred KPIs
```

Five scripts ship, one per story. The sales team can mix-and-match depending on the audience and time available.

---

## 9.13 Summary

The demo dataset is a deliberate product, not a byproduct. Northwind Co. is a plausible target client with a coherent story; the five embedded scenarios surface specific KPI behaviors that map to specific sales conversations; the generator is deterministic, scalable, and tested.

Key design choices recap:

- **One company, one story, embedded narratives.** Five scenarios cover quarterly demo opportunities and exercise every module's distinctive features.
- **Three scales, same story.** Small for dev, Medium for demos and CI, Large for load testing.
- **Source-system shape compliance.** Generator output matches each source's API shape so the entire pipeline (staging → core → marts) is exercised.
- **Known KPI values for validation.** ~3,000 expected metric values gate CI; the demo is a regression-prevention asset.
- **Sales-ready scripts.** Per-story playbooks that the sales team uses verbatim.

Beyond the technical artifact, the demo dataset is what makes the pack **demonstrable before sale** — a prospect can see their own Power BI populated with realistic numbers in 15 minutes, run questions through the AI assistant, and form an opinion before any commercial conversation. That experience is the strongest predictor of close rate for productized data platforms.

The next section (Section 10) defines the Power BI dashboard pack — the three dashboards that surface Section 9's demo data and Section 5's KPIs to actual users.

---

**Previous:** [Section 8: Governance Baseline](./08_governance_baseline.md)
**Next:** [Section 10: Power BI Dashboard Pack](./10_powerbi_dashboard_pack.md)
