# Section 11: Open-Source vs. Pro Split

> **Document status:** Draft v1
> **Audience:** Spark Analytics leadership, sales team, prospects evaluating the pack, open-source contributors, internal pricing committee
> **Purpose:** Consolidate every open-source vs. proprietary decision made across Sections 3–10 into one definitive view. Useful for internal pricing decisions, sales conversations, and contributor onboarding.

---

## 11.1 Why this section exists

The open/pro split has been specified in every prior section: KPIs per tier in Section 5, model code per tier in Section 4, connector code in Section 6, semantic layer in Section 7, dashboards in Section 10. Each section made local decisions about what to ship freely vs. as part of the proprietary tier.

Section 11 is the **synthesis**. It does not introduce new splits — every decision in this section originates in another section. It exists because:

- Sales conversations need a single artifact to point at when explaining "what do I get free vs. paid"
- Internal pricing decisions need a complete picture of what value sits where
- Contributors to the open-source repo need clarity on what's in scope for community PRs
- Procurement reviews want to verify the "open core" claim is real, not marketing

Where this section conflicts with another section, the other section wins. Section 11 is a synthesis, not a re-specification.

---

## 11.2 The distribution model (recap)

Per ADR-001, the pack uses a **hybrid open-core** distribution. Three components:

1. **Open-source core** — MIT licensed, on GitHub, freely usable
2. **Proprietary modules** — commercially licensed, available to paying clients
3. **Implementation services** — consultancy time provided by Spark Analytics

The strategic rationale was settled early: the open-source core is a lead-generation engine that pre-qualifies prospects, the proprietary modules protect commercial differentiation, and services capture the bulk of revenue while the product matures. This decision is permanent for v1.

---

## 11.3 What's in each tier — component by component

The complete inventory. Each row points to where the underlying decision was originally made.

### Data foundation

| Component | OSS | Pro | Source |
|---|---|---|---|
| Bronze layer raw schemas | ✅ | – | Section 2.2 |
| Silver/staging models (all 5 sources) | ✅ | – | Section 6 |
| Intermediate models (identity resolution, enrichment) | ✅ | – | Section 4 Part 1 §4.3 |
| Gold/core layer — all 9 dimensions | ✅ | – | Section 4 Part 1 |
| Gold/core layer — all 9 facts | ✅ | – | Section 4 Part 2 |
| Audit columns (8-column footer on every table) | ✅ | – | Section 4 Part 2 §4.31, ADR-002 |
| `add_audit_columns` macro | ✅ | – | Section 4 Part 3 §4.47 |
| Identity resolution (Tier 1+2 — email and phone) | ✅ | – | Section 4 Part 1 §4.3 |
| Identity resolution (Tier 3 — fuzzy name+address) | ✅ | – | ADR-003 |

**Observation:** The entire canonical data model is open source. This is the largest single body of code in the pack, and shipping it free is the cornerstone of the "open core" claim. A retailer can stand up the warehouse layers without paying.

### KPI catalog (25 KPIs)

Per Section 5.15: **14 OSS, 11 Pro**. The full list:

| KPI | Tier | Source |
|---|---|---|
| Gross Merchandise Value (GMV) | OSS | §5.4 KPI 1 |
| Net Revenue | OSS | §5.4 KPI 2 |
| Order Count | OSS | §5.4 KPI 3 |
| Average Order Value (AOV) | OSS | §5.4 KPI 4 |
| Revenue Growth % | OSS | §5.4 KPI 5 |
| Refund Rate | **Pro** | §5.4 KPI 6 |
| Return Rate | **Pro** | §5.4 KPI 7 |
| Revenue by Channel | **Pro** | §5.4 KPI 8 |
| Tax Collected | OSS | §5.4 KPI 9 |
| Active Customers (30-day) | OSS | §5.5 KPI 10 |
| Active Customers (90-day) | OSS | §5.5 KPI 11 |
| New Customers | OSS | §5.5 KPI 12 |
| Repeat Customer Count | OSS | §5.5 KPI 13 |
| Repeat Purchase Rate | OSS | §5.5 KPI 14 |
| Customer Lifetime Value (basic) | **Pro** | §5.5 KPI 15 |
| Average Time Between Orders | **Pro** | §5.5 KPI 16 |
| Customer Acquisition Cost by Channel | **Pro** | §5.5 KPI 17 |
| Return on Ad Spend by Channel | **Pro** | §5.5 KPI 18 |
| Email Engagement Rate | **Pro** | §5.5 KPI 19 |
| Total Inventory Value | OSS | §5.6 KPI 20 |
| Inventory Turnover | **Pro** | §5.6 KPI 21 |
| Days of Supply | OSS | §5.6 KPI 22 |
| Stockout Rate | OSS | §5.6 KPI 23 |
| Sell-Through Rate | **Pro** | §5.6 KPI 24 |
| Slow-Moving SKU Count | **Pro** | §5.6 KPI 25 |

**Observation:** The 5 most foundational sales metrics (GMV, Net Revenue, Order Count, AOV, Revenue Growth %) plus Tax are OSS — the absolute basics every retailer needs. The Pro tier concentrates on KPIs that require multi-source joins (Refund Rate joins orders+refunds), cohort logic, attribution, or enrichment with pro-only data columns (e.g., `is_slow_mover` flag).

### Connectors

Per Section 6.10: **all 5 connectors are OSS**.

| Connector | OSS | Pro |
|---|---|---|
| Shopify staging | ✅ | – |
| Stripe staging | ✅ | – |
| Google Analytics 4 staging | ✅ | – |
| Meta Ads staging | ✅ | – |
| Klaviyo staging | ✅ | – |
| Source mapping seed framework | ✅ | – |
| Pre-built category mapping libraries (apparel, beauty, home) | – | ✅ (Section 4 Part 1 §4.4) |
| Extended channel mapping seed library (50+ pre-mapped sources) | – | ✅ (Section 4 Part 1 §4.6) |

**Observation:** Connectors are commodity. Shipping them OSS removes the "vendor lock-in" objection in sales and signals genuine open-core. The proprietary mapping libraries are the value-add — they save weeks of category cleanup work for every client.

### Semantic layer

Per Section 7.4: **entire semantic layer is proprietary**.

| Component | OSS | Pro |
|---|---|---|
| MetricFlow YAML for all 25 metrics | – | ✅ |
| Business glossary | – | ✅ |
| Entity ontology | – | ✅ |
| AI metadata (synonyms, examples, domain facts) | – | ✅ |
| Pro KPI definitions in YAML | – | ✅ |
| OSS KPI definitions in YAML | – | ✅* |

\* Even the OSS KPIs' MetricFlow encoding is proprietary. A free-tier user has the SQL formulas (in OSS dbt models) but not the MetricFlow YAML. This is intentional — the semantic layer is the consumption abstraction; consumers (Power BI, AI assistant) require the proprietary tier to query metrics consistently.

**Observation:** The semantic layer is where the highest concentration of pro IP sits. A free-tier user gets the underlying SQL and can query mart tables directly with their own BI tool's DAX/LookML/whatever. The proprietary value is the **abstraction layer that makes metrics consistent across tools**.

### Dashboards

Per Section 10.2: **all three dashboards are proprietary**.

| Component | OSS | Pro |
|---|---|---|
| Executive Summary `.pbix` | – | ✅ |
| Customer 360 `.pbix` | – | ✅ |
| Inventory Health `.pbix` | – | ✅ |
| Pack default theme (`SparkDefault.json`) | – | ✅ |
| Client-brand theme template | – | ✅ |
| Style guide | – | ✅ |
| Installation guide | – | ✅ |
| User navigation guide | – | ✅ |

**Observation:** Dashboards are the most visible commercial differentiation. A prospect who tries to replicate weeks of Power BI design work from OSS code alone will struggle — the visual design itself is hard to clone, even if the data is open.

### Demo data

Per Section 9.10:

| Component | OSS | Pro |
|---|---|---|
| Synthetic data generator (Python scripts) | ✅ | – |
| Northwind Co. configuration | ✅ | – |
| Story arc modules (5 scenarios) | ✅ | – |
| Locally-regeneratable datasets (all tiers via `generators/main.py`) | ✅ | – |
| Pre-loaded Snowflake share (`SPARK_RETAIL_DEMO`) — instant zero-copy clone | – | ✅ |
| Additional pro scenarios (AI-ready metadata simulation, embedded analytics tenant simulation) | – | ✅ |
| Expected KPI values for CI validation | – | ✅ |
| Demo scripts and sales scenarios | – | ✅ |

**Observation:** The generator is open source, and an OSS user can produce any tier locally. The **convenience artifacts** — pre-loaded Snowflake share for instant demos, AI/embedded simulation extras, validation values, sales scripts — are pro. An OSS user can demo to themselves with a few minutes of setup; only paying clients get the polished sales-ready environment.

### Governance

Per Section 8:

| Component | OSS | Pro |
|---|---|---|
| 8-column audit footer | ✅ | – |
| `metadata.dbt_run_log` table | ✅ | – |
| `metadata.lineage_edges` view | ✅ | – |
| PII tagging on canonical columns | ✅ | – |
| `pii_mask` macro | ✅ | – |
| `customer_erasure` macro (GDPR/CCPA) | ✅ | – |
| Default ownership / classification YAML files | ✅ | – |
| 7 standard Snowflake roles | ✅ | – |
| Data Operations dashboard (Power BI) | – | ✅ |
| Quarterly access review report generator | – | ✅ |

**Observation:** Governance machinery is mostly open source. The dashboards and reports that surface governance posture visually are pro. This pattern repeats elsewhere — **the substance is OSS, the polish is pro**.

### Implementation standards and tooling

Per Section 4 Part 3:

| Component | OSS | Pro |
|---|---|---|
| Materialization strategy (per-fact decisions) | ✅ | – |
| Incremental load patterns + lookback macros | ✅ | – |
| SCD2 snapshot strategy | ✅ | – |
| Test framework (4 categories) | ✅ | – |
| All schema/business-rule tests | ✅ | – |
| Source freshness configuration | ✅ | – |
| CI/CD pipeline templates | ✅ | – |
| Error handling and alerting framework | ✅ | – |
| Cost monitoring (`metadata.query_cost_log`) | ✅ | – |
| 9 OSS macros (audit, keys, source mapping, PII, etc.) | ✅ | – |
| 6 Pro macros (RFM, cohorts, attribution, churn, velocity) | – | ✅ |

**Observation:** Engineering discipline is open source. Advanced analytical macros are pro.

### Documentation

| Component | OSS | Pro |
|---|---|---|
| README, installation guide, contribution guide | ✅ | – |
| dbt docs site (auto-generated) | ✅ | – |
| Connector documentation (per-source READMEs) | ✅ | – |
| Operational runbook | – | ✅ |
| Sales playbooks (per-story demo scripts) | – | ✅ |
| Client implementation handbook | – | ✅ |
| User training materials | – | ✅ |

**Observation:** Technical docs are open. Sales- and operations-focused docs are pro.

---

## 11.4 Services tier

Beyond OSS code and Pro product, Spark Analytics provides services. These are not "tier 3 of the product" — they are a separate revenue stream that wraps the product.

| Service | Typical scope | Revenue model |
|---|---|---|
| Implementation engagement (4–6 weeks) | Deploy the pack against client data, configure dashboards, train team | Project-based, $50K–$150K |
| Custom connector development | Build new connector for a client's bespoke system | Project-based, $15K–$40K |
| Custom dashboard development | Build a client-specific dashboard beyond the three pack defaults | Project-based, $8K–$25K |
| Ongoing managed service | Run dbt, monitor freshness, respond to data issues | Monthly subscription, $5K–$15K/month |
| Training and enablement | Train client analytics team to extend the pack | Daily rate, $4K–$8K/day |
| Strategic data advisory | Architecture review, roadmap planning, vendor evaluation | Retainer or project |

Services are the **bulk of Spark's revenue** in v1. The product (open-source + pro tier together) is a credibility builder and a service-anchor. As the product matures (v2, v3), the product-to-services ratio shifts toward product.

---

## 11.5 Pricing model

The full pricing model is finalized outside this document (commercial confidential). This section documents the **structure**, not the specific dollar amounts.

### Open-source tier — free

- All OSS components per §11.3
- Community support via GitHub Issues and Discord
- No SLA, no guaranteed response time
- No implementation services included
- Suitable for clients who have an analytics engineering team and want to self-implement

### Pro tier — annual license

Structured as an annual subscription. Pricing tiers based on client GMV:

| GMV tier | Annual license fee (indicative — not final) |
|---|---|
| $5M – $25M | Base tier |
| $25M – $75M | Mid tier (~2× base) |
| $75M – $200M | Enterprise tier (~4× base) |
| $200M+ | Custom pricing |

Includes:
- All Pro components per §11.3
- 30-day implementation playbook
- Email + Slack support (business hours)
- Quarterly product updates and bug fixes
- Access to private GitHub repository for pro modules

### Services tier — separate

Quoted per engagement (see §11.4 for typical scope).

### Why GMV-based pricing

Three reasons:

1. **Aligns with client value capture.** A client doing $50M GMV gets more value from the warehouse than one doing $10M (more data, more decisions, more revenue at stake).
2. **Removes seat-counting incentives.** Per-seat pricing creates perverse incentives — clients limit access to save money, which limits adoption of the pack.
3. **Predictable for clients.** GMV is a number clients already track. Tier-based pricing is transparent — no surprise overages.

---

## 11.6 The strategic case for each tier

A buyer asks: "Why would I pay for the Pro tier when the OSS tier exists?" The honest answers per concern:

### "Could I just implement everything myself using the OSS code?"

Yes, technically. Realistically:
- You would need 1–2 analytics engineers for 3–6 months
- You would build your own semantic layer encoding (the abstraction that makes metrics consistent)
- You would build your own Power BI dashboards from scratch (3–4 weeks of design)
- You would write your own demo data and validation
- Total cost: ~$150K–$300K in headcount time, before factoring in the 6-month delay in business value

The Pro tier delivers all of this in 4–6 weeks for less.

### "What if Spark Analytics goes out of business?"

The OSS core continues to work. You own the SQL, the canonical model, the connectors. You'd lose:
- Updates to the semantic layer YAML
- Dashboard maintenance and updates
- Support

But your warehouse keeps running. This is a deliberate property of open-core distribution — clients are not trapped.

### "Can we start with OSS and upgrade to Pro later?"

Yes. The Pro tier is purely additive — installing it does not break the OSS deployment. Many clients start with OSS for evaluation (typically 2–8 weeks of self-experimentation), then upgrade for the dashboards and semantic layer when they want to ship to non-technical users.

### "What if I only need 1 of the 3 modules?"

The Pro tier ships all three modules together. Clients can deploy only the modules they need (per Section 3) — the unused dashboards are simply not used. There is no per-module pricing in v1; it adds pricing complexity without meaningfully reducing client cost.

---

## 11.7 The adoption journey

A typical client moves through three phases:

### Phase 1 — Evaluation (weeks 0–8)

- Discovers the pack via GitHub or sales outreach
- Clones the OSS repo
- Runs the demo data locally
- Reads documentation
- May join Discord/Slack community

**Outcome:** Either gives up (most), or schedules a Pro tier conversation (target: ~5% of OSS adopters).

### Phase 2 — Pro implementation (weeks 8–14)

- Signs Pro license
- Engages Spark Analytics for 4–6 week implementation
- Deploys against real client data
- Dashboards go live for executives

**Outcome:** Working warehouse with weekly KPI reviews.

### Phase 3 — Ongoing operation (months 4+)

- Renews Pro license annually
- May purchase managed service or strategic advisory
- May commission custom connector or dashboard work
- Provides feedback that influences pack roadmap

**Outcome:** Long-term client relationship, recurring revenue, reference customer for sales.

The OSS-to-Pro conversion rate is the **single most important metric for Spark Analytics' business**. v1 target: 5% within 8 weeks of OSS adoption. v2 target: 8% within 4 weeks (informed by better onboarding tooling).

---

## 11.8 What's deliberately not in either tier

Honest scope statement — capabilities the pack does not provide at any tier.

| Capability | Why excluded |
|---|---|
| Real-time / streaming pipelines | v2 — not in MVP scope |
| Multi-warehouse support (BigQuery, Databricks) | Snowflake-only in v1 per ADR-001 |
| Non-English dashboards | v2 — localization is its own effort |
| Looker / Tableau / Metabase dashboard equivalents | Power BI only in v1 per ADR-001 |
| ML-based predictive metrics (predicted LTV, churn probability) | v2 — flagged as "Pro v2" in Section 5 |
| Full marketing attribution (multi-touch, MMM) | v2 |
| Subscription / recurring revenue analytics | v2 — module deferred |
| Customer service analytics | v2 — connectors deferred |
| Fulfillment / logistics analytics | v2 — module deferred |
| B2B / wholesale analytics | v2 — different sales process |
| Loyalty program analytics | v2 — diverse platforms |
| Marketplace analytics (Amazon, eBay) | v2 |
| Mobile-optimized dashboards | v2 — Power BI Mobile works but layouts not optimized |
| Embedded analytics framework | v2 — flagged in Sections 2.2 and 7.14 |
| AI assistant (natural language querying) | v2 — built on top of Section 7's semantic layer |
| SOC 2 / ISO 27001 certification of the pack | Not pursued in v1 (Section 8.13) |
| Real-time DLP scanning | Not in v1 |
| Customer-managed encryption keys | Snowflake supports; pack-level configuration manual in v1 |

These are documented honestly so prospects can decide if v1 fits their needs. Anyone needing a deferred capability either waits for v2 or commissions custom work as a service.

---

## 11.9 Comparison to similar open-core products

The hybrid open-core model isn't novel — it's the dominant model for modern data infrastructure. Reference points for prospects evaluating the pack:

| Product | OSS core | Pro tier | Services |
|---|---|---|---|
| **dbt Labs** | dbt Core (free, MIT) | dbt Cloud (managed, $100+/seat/month) | dbt Labs consulting |
| **Airbyte** | Airbyte Core (free) | Airbyte Cloud + Enterprise | Airbyte services |
| **Metabase** | Metabase OSS (free) | Metabase Enterprise + Cloud | Limited |
| **HashiCorp** | Terraform / Vault OSS | Terraform Cloud / Vault Enterprise | HashiCorp services |
| **GitLab** | GitLab CE (free) | GitLab Premium / Ultimate | GitLab Services |
| **Spark Retail Pack** (this pack) | Core dbt models + connectors + governance | Semantic layer + dashboards + advanced metrics | Spark Analytics implementation |

All of these companies are profitable or path-to-profitable on the open-core model. The pack follows the same blueprint deliberately.

**Differences from these comparison points:**

- Most of the above are general-purpose platforms; the pack is **industry-specific** (retail)
- The pack's pro tier emphasizes **vertical depth** (dashboards for retailers, retail KPIs) rather than horizontal scale
- Services revenue is more central to Spark Analytics than to, say, dbt Labs at this stage

---

## 11.10 Risks of the open-core model

Honest acknowledgment — every open-core product faces certain failure modes. How the pack addresses each:

| Risk | Mitigation |
|---|---|
| **OSS users never convert.** Most users get value from the free tier and never pay. | Pro tier offers clear discontinuous value (dashboards, semantic layer abstraction) that's hard to replicate. Sales engagement targets active OSS users showing real deployment signals. |
| **A competitor forks the OSS code and undercuts.** | Mitigated by the proprietary tier holding the highest-value components. A fork inherits the foundation but not the dashboards, semantic layer, or implementation expertise. |
| **OSS support burden eats into services time.** | Community-supported via GitHub Issues / Discord — explicit no-SLA. Paying clients get prioritized support; OSS users get best-effort. |
| **Pro tier is perceived as "the real product" and OSS as a teaser.** | Active investment in OSS quality — bug fixes, documentation, contributor onboarding. The OSS tier must be genuinely useful, not a crippled demo. |
| **Strategic confusion: are we a product company or a services company?** | Explicit framing: v1 is services-led with product building credibility. v2-v3 shifts toward product-led. Quarterly metric review of the product/services ratio guides the transition. |
| **License erosion: Pro features leak into the OSS repo via PRs.** | Code review policy explicitly checks for pro-only logic in PRs. The pro repo is a separate private repository. Pro macros are tagged with `@pro_only` decorators (where applicable). |

These risks are not theoretical — they have killed open-core companies. The pack's strategy assumes managed risk, not eliminated risk.

---

## 11.11 The contribution model

A defining feature of OSS is community contribution. The pack accepts contributions to the OSS core under these conditions:

| Contribution type | Accepted? |
|---|---|
| Bug fixes in OSS models | Yes |
| Documentation improvements | Yes |
| New connector for v2 (if community-developed) | Yes, with maintainer review |
| New OSS macros (additive) | Yes |
| Tests and CI improvements | Yes |
| Refactoring of OSS models | Maintainer review required (avoid breaking changes) |
| Adding pro features to OSS | **No** — would erode commercial differentiation |
| Modifying the canonical model's column schema | Major version review; rare |

Contributors sign a CLA (Contributor License Agreement) on first PR. This is a standard practice for open-core projects — it ensures Spark Analytics retains the right to relicense the OSS code under the proprietary license when bundled into the Pro tier.

A CONTRIBUTING.md ships with the pack that documents all of this clearly.

---

## 11.12 Versioning and the open/pro boundary

The OSS and Pro tiers version together. A Pack v1.2 release means OSS v1.2 plus Pro v1.2; clients can mix versions across major boundaries but not minor.

| Scenario | Versioning behavior |
|---|---|
| Bug fix in an OSS model | OSS patch version bump (1.2.0 → 1.2.1); Pro stays at 1.2.0 |
| New OSS feature added | OSS minor version bump; Pro stays at compatible version |
| Breaking change to canonical model | Both OSS and Pro major version bump together |
| New Pro feature (e.g., new dashboard) | Pro minor version bump; OSS unaffected |

This is mechanical and documented in Section 4 Part 3 §4.38. The point for §11: clients are never forced to upgrade Pro to get an OSS bug fix, and OSS users see ongoing improvements without being locked out of the latest patches.

---

## 11.13 The narrow questions a prospect asks

A consolidated FAQ — every question a prospect or procurement team has actually asked during early sales conversations. Each answer is shorter than the corresponding section but points there for detail.

**Q: Is the OSS tier crippled?**
A: No. It includes the full canonical data model, all 5 connectors, 14 of 25 KPIs, governance machinery, audit columns, demo data generator, and CI tooling. A retailer with an analytics engineering team can build a working warehouse with OSS alone.

**Q: What does Pro buy me that I can't build myself?**
A: Three things in priority order: the Power BI dashboard pack (weeks of design work), the semantic layer abstraction (single source of truth for metrics across tools), and the proprietary advanced KPIs (LTV, attribution, sell-through cohorts). Plus support and implementation services.

**Q: Can I evaluate Pro before paying?**
A: Yes — Spark Analytics maintains a hosted demo environment with all Pro components running on the Northwind Co. synthetic data. Prospects evaluate without committing.

**Q: What if I want a feature that's deferred to v2?**
A: Either wait for v2 or commission custom work as a service. The pack's roadmap is shared with paying clients quarterly.

**Q: Is there a perpetual license option?**
A: No, only annual subscription. This is deliberate — perpetual licenses erode the renewal motion that funds ongoing development.

**Q: What happens to my data if I cancel?**
A: All your data stays in your Snowflake account. The OSS models continue to run; the Pro dashboards and semantic layer stop updating but remain functional (read-only on last refresh). You lose updates and support; you don't lose data.

**Q: Can I see the Pro source code before signing?**
A: Yes, under NDA. Most clients don't request this; the demo environment is usually sufficient.

**Q: Will Spark sell my data?**
A: No. The pack is deployed in your Snowflake account; Spark Analytics never receives client data unless commissioned to. This is documented in the master services agreement.

---

## 11.14 Summary

The Spark Retail Pack's commercial structure:

- **Open-source core** — entire canonical data model, all 5 connectors, 14 of 25 KPIs, governance machinery, demo generator, CI tooling, 9 OSS macros. Free, MIT licensed, on GitHub.
- **Proprietary tier** — semantic layer (all 25 KPIs encoded in MetricFlow), 3 Power BI dashboards, 11 Pro KPIs, advanced macros (RFM, attribution, cohorts), AI metadata, polished demo artifacts, operational documentation. Annual license, GMV-tiered.
- **Services** — implementation engagements ($50K–$150K), custom development, ongoing managed service, strategic advisory.

The model is identical in shape to dbt Labs, Airbyte, Metabase, and HashiCorp. The differentiation is **vertical depth** (retail-specific) rather than horizontal scale.

The open/pro boundary is drawn so that:

- A free-tier user gets genuine value (working warehouse)
- A paying client gets discontinuous value (working business reporting in 4–6 weeks)
- The proprietary tier protects the components hardest to clone (dashboards, semantic layer, expertise)
- Contributions to the OSS core are welcome but cannot drift into pro territory

The remaining work is the build itself. Section 12 sequences it into phases with effort estimates.

---

**Previous:** [Section 10: Power BI Dashboard Pack](./10_powerbi_dashboard_pack.md)
**Next:** [Section 12: Build Roadmap](./12_build_roadmap.md)
