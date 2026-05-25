# Section 13: Operational Best Practices

> **Document status:** Draft v1
> **Audience:** Client implementation teams, Spark Analytics services team, partners, paying clients' operations teams
> **Purpose:** Consolidate operational practices that apply *after* the pack is deployed — runbooks, support procedures, upgrade patterns, training paths, and the engagement model between Spark Analytics and clients.

---

## 13.1 What this section defines

Section 4 Part 3 covered **engineering standards** — how the dbt project is built, tested, and shipped. Section 13 covers **operational practices** — how the deployed pack is run, supported, upgraded, and trained on.

These are deliberately separated because they have different audiences and lifecycles:

- Section 4 Part 3 governs contributors and engineers writing models
- Section 13 governs implementation consultants, client analytics teams, and Spark Analytics support

This section synthesizes operational decisions that emerge from earlier sections — it introduces no new design, but consolidates "how do you actually run this thing" into a single reference for client engagements and internal operations.

Where this section conflicts with another section, the other section wins.

---

## 13.2 The deployment runbook

A typical client implementation follows a 4–6 week engagement. The day-by-day runbook below is the **default sequence**; deviations are normal and documented per-client.

### Week 0 — Kickoff and prerequisites

| Day | Activity | Owner |
|---|---|---|
| Pre-kickoff | Signed Pro license, signed master services agreement | Both |
| Day 1 | Kickoff meeting: confirm scope, decision points (per §13.3), success criteria | Both |
| Day 2 | Client provisions Snowflake account (or shares existing) | Client |
| Day 2–3 | Client provides credentials for the 5 source systems (Shopify, Stripe, GA4, Meta, Klaviyo) | Client |
| Day 3 | Spark configures dbt Cloud / dbt Core environment (per ADR-004 choice) | Spark |
| Day 4 | First `dbt build` against demo data in client's Snowflake account | Spark |
| Day 5 | Kickoff retro: any blockers, any scope changes | Both |

### Week 1 — Foundation

| Day | Activity |
|---|---|
| Day 6 | Snowflake roles configured (7 roles per Section 2.5) |
| Day 7 | Ingestion tool (Fivetran/Airbyte) connected to all 5 sources |
| Day 8–9 | First real-data load into bronze; staging models run; data quality issues surfaced |
| Day 10 | Initial canonical model run (`dim_customer`, `fact_orders`) on real data |

**Validation gate:** End of Week 1 — `dim_customer` populates correctly, `fact_orders` matches client's own order count within 0.5%.

### Week 2 — Core build-out

| Day | Activity |
|---|---|
| Day 11–12 | Remaining dimensions and facts run on real data |
| Day 13 | Identity resolution validated against known customers |
| Day 14 | Marts run; KPIs computed |
| Day 15 | Initial Power BI connection (Path 1 or Path 2 per ADR-004); first dashboard loaded |

**Validation gate:** End of Week 2 — at least 5 KPIs (GMV, Net Revenue, Order Count, AOV, Active Customers 30d) match client's existing reports within tolerance.

### Week 3 — Dashboards and customization

| Day | Activity |
|---|---|
| Day 16–17 | All three dashboards deployed |
| Day 18 | Client brand applied (theme customization per Section 10.16) |
| Day 19 | Custom KPI labels applied if client uses different terminology |
| Day 20 | Cross-dashboard navigation verified |

**Validation gate:** End of Week 3 — dashboards meet performance budgets (Section 10.10).

### Week 4 — Governance and training

| Day | Activity |
|---|---|
| Day 21 | Governance artifacts deployed (ownership.yml, classification.yml, retention.yml) |
| Day 22 | PII access tested for both standard and PII viewer roles |
| Day 23 | First analyst training session (1 day virtual, per §13.5) |
| Day 24 | Engineer training session (3-day hands-on) begins |
| Day 25 | Quality alert routing tested |

**Validation gate:** End of Week 4 — at least 3 client analysts can navigate the dashboards confidently and write basic ad-hoc SQL queries against the core.

### Weeks 5–6 — Go-live and hypercare

| Day | Activity |
|---|---|
| Day 26 | Final go/no-go review |
| Day 27 | Production cutover (refresh schedule live; client begins using dashboards for actual reporting) |
| Days 28–40 | Hypercare period — Spark on-call for any operational issues; daily check-ins for first week, then weekly |

**Go-live criteria** (must all be true):

1. All canonical model tests passing in production
2. Source freshness within SLA for all 5 sources for 3 consecutive days
3. KPI values match client's prior reporting within 1% for the latest closed month
4. At least one stakeholder (CMO, CFO, or COO) signs off on their respective dashboard
5. Erasure macro tested with a synthetic customer record
6. Quarterly access review schedule scheduled
7. Documentation handed off (implementation playbook, runbooks, user guides)

If any criterion fails, go-live is delayed until resolved. The engagement budget includes 1 week of buffer for this; longer delays are billed as services time.

---

## 13.3 Decision points at kickoff

Before implementation begins, several decisions must be made jointly. Each maps to a section or ADR that documents the trade-off.

| Decision | Default | Source |
|---|---|---|
| dbt Cloud vs. dbt Core for Semantic Layer | Path 1 (Cloud) for production-grade clients; Path 2 (Core fallback) for evaluation or budget-constrained | ADR-004 |
| Reporting currency | Client's primary operating currency (USD for most) | Section 4 Part 1 §4.11 |
| Reporting timezone | Client's headquarters timezone | Section 4 Part 1 §4.7 |
| Snowflake region | Client's existing if they have one; else `us-east-1` (US clients) or `eu-west-1` (EU clients) | Section 2.5 |
| Initial PII handling level | Full hashing in non-dev environments | Section 8.5 |
| Retention horizons | Section 8.9 defaults unless regulatory or client preference says otherwise | Section 8.9 |

These are documented in the client's kickoff document and revisited at the engagement retrospective.

---

## 13.4 Support and on-call model

Spark Analytics offers three support tiers. Each maps to client tier (OSS, Pro, Pro + Managed Service).

### Tier 1 — Community support (OSS users)

| Channel | GitHub Issues, Discord community |
|---|---|
| Response time | Best effort — community-moderated |
| SLA | None |
| Severity escalation | Not available |
| Cost | Free |

### Tier 2 — Pro support (annual license clients)

| Channel | Email, Slack Connect channel, GitHub Issues (priority queue) |
|---|---|
| Response time | First response within 1 business day (Mon–Fri, 9am–5pm client timezone) |
| Severity escalation | P0/P1 issues route to engineering on-call |
| SLA | Resolution within reasonable effort — no hard guarantees |
| Cost | Included in Pro annual license |

### Tier 3 — Managed service (Pro + Managed Service)

| Channel | Dedicated Slack channel, 24×5 phone, named technical account manager |
|---|---|
| Response time | First response within 1 hour business hours, 4 hours nights/weekends |
| Severity escalation | P0 issues page on-call engineer directly |
| SLA | Documented per-issue SLAs by severity |
| Cost | Monthly retainer ($5K–$15K/month per Section 11.4) |

### Incident severity classification

| Severity | Definition | Examples | Response |
|---|---|---|---|
| **P0 — Critical** | Production warehouse completely down; no data flowing | Snowflake outage cascading to pack; complete dbt build failure preventing all refresh | All-hands; named TAM and engineering lead engaged |
| **P1 — High** | Major functionality broken; some dashboards/KPIs unavailable | Wrong KPI values on Executive Summary; key dashboard not refreshing | Engineering lead engaged; status updates every 2 hours |
| **P2 — Medium** | Degraded experience; workarounds exist | Slow dashboard load; minor data quality issue affecting one dimension | Standard support engineer; status updates daily |
| **P3 — Low** | Cosmetic issues; documentation requests; feature questions | Misspelled label on a dashboard; clarification on metric formula | Standard support queue; resolved next sprint |

P0 and P1 escalate automatically based on the alert routing defined per Section 8.8.

---

## 13.5 Client training paths

Spark Analytics offers four training tracks. Each is included in the appropriate engagement; additional training is billed at services rates.

### Track 1 — Analyst onboarding (1 day virtual)

For business analysts who consume dashboards and write occasional ad-hoc SQL.

| Hour | Topic |
|---|---|
| 1 | Overview of the pack, modules, and what's possible |
| 2 | Dashboard navigation walkthrough (all three dashboards) |
| 3 | Slicer architecture, drill-through patterns, filtering |
| 4 | Reading lineage, finding metric definitions, the glossary |
| 5 | Writing basic SQL against mart tables |
| 6 | Common questions and where to look for answers |
| 7 | Hands-on exercises with the demo data |
| 8 | Q&A and certification (informal) |

**Outcome:** Analyst can answer most weekly business questions independently.

### Track 2 — Engineer onboarding (3 days hands-on)

For analytics engineers who will extend the pack.

| Day | Focus |
|---|---|
| Day 1 | The canonical data model — dimensions, facts, audit columns, identity resolution |
| Day 2 | Macros, tests, CI/CD, debugging failed builds, the staging→core→marts flow |
| Day 3 | Adding custom models, the semantic layer YAML, dashboards customization, upgrade procedures |

**Outcome:** Engineer can write new models that follow pack conventions, debug data quality issues, and lead minor upgrades.

### Track 3 — Admin training (½ day)

For security and platform admins.

| Topic | Time |
|---|---|
| Snowflake role hierarchy and access patterns | 1 hour |
| PII handling and the erasure workflow | 1 hour |
| Cost monitoring and warehouse sizing | 1 hour |
| Audit log review and quarterly access review process | 1 hour |

**Outcome:** Admin can manage access, run quarterly reviews, and respond to GDPR/CCPA requests.

### Track 4 — Train-the-trainer (2 days, larger clients)

For client-side analytics leaders running larger teams. Equips them to deliver Tracks 1 and 3 internally as new team members join.

**Outcome:** Client achieves training independence; Spark Analytics handles only edge cases and major upgrades.

### Future certification (v2 consideration)

A formal "Spark Retail Pack Certified Engineer" credential is under consideration for v2. Likely a 90-minute exam covering the engineer track curriculum.

---

## 13.6 Upgrade and migration patterns

The pack versions semantically (Section 4 Part 3 §4.38). Upgrades fall into three categories.

### Patch upgrades (v1.0.0 → v1.0.1)

**What changes:** Bug fixes, no schema changes, no breaking changes.
**Effort:** ~30 minutes including validation.

```
1. Review release notes
2. Bump package version in client's packages.yml
3. Run `dbt deps`
4. Run `dbt build` in staging
5. Validate KPI values match expected (no regressions)
6. Deploy to production
```

Patch upgrades can be self-served by the client's engineering team. Spark Analytics support is available on request.

### Minor upgrades (v1.0.x → v1.1.0)

**What changes:** Additive only — new columns, new tests, new macros, new dashboards. No removed or renamed columns.
**Effort:** ~half day including validation.

```
1. Review release notes carefully; flag any new dependencies or recommended actions
2. In staging branch: bump package version, run `dbt deps`
3. Run `dbt build --select state:modified+`
4. Verify all new columns populate as expected
5. Update any custom code that may benefit from new columns
6. Run regression validation
7. Deploy to production during low-traffic window
```

Pro clients get a written release-summary document for each minor release; Managed Service clients can request Spark Analytics to perform the upgrade as part of the retainer.

### Major upgrades (v1.x → v2.0)

**What changes:** Potentially breaking — column renames, structural changes, deprecated patterns removed.
**Effort:** 1–2 weeks for a typical client; up to 4 weeks for heavily customized deployments.

```
1. Read the v2 migration guide (ships with v2.0 release)
2. Identify client-specific customizations that may need updates
3. Run the v2 migration script in staging
4. Manual review of any unmigratable customizations
5. Full regression test against expected KPI values
6. Side-by-side comparison with production for 1 week
7. Cutover during scheduled maintenance window
8. Rollback plan documented (Snowflake Time Travel + Git tag for the dbt project)
```

Major upgrades are a Spark Analytics services engagement by default. Managed Service clients include one major upgrade per year in their retainer.

### Custom code preservation

Throughout all upgrade tiers, client-side custom models live in dedicated folders (`models/client_custom/`) that the upgrade scripts never touch. The pack's models live in `models/core/`, `models/marts/`, etc. The separation is documented at implementation kickoff (per Section 10.16's customization model).

---

## 13.7 Engagement model

The full engagement lifecycle from first contact to renewal.

### Initial implementation (weeks 1–6)

Per §13.2 above. Fixed-scope, fixed-fee engagement at $50K–$150K depending on client tier (per Section 11.4).

### Hypercare period (weeks 7–10)

Spark Analytics on-call for the first 4 weeks post go-live. Daily check-ins for the first week; weekly for the next 3. Any issues that surface in production get prioritized response. No additional charge — included in the implementation engagement.

### Ongoing operation (month 4 onwards)

The client operates the pack day-to-day. Spark Analytics relationship is one of:

| Engagement type | What it covers | Cost |
|---|---|---|
| **Pro license only** | Software updates, email/Slack support, annual review | Annual subscription |
| **Pro + Managed Service** | All of the above plus monitoring, on-call, monthly health checks | Annual subscription + monthly retainer |
| **Pro + Project work** | Pro license, plus specific projects (custom connectors, new dashboards) as scoped | Annual subscription + project fees |
| **Pro + Strategic advisory** | Pro license, plus quarterly strategy reviews, roadmap input, architecture reviews | Annual subscription + monthly retainer |

Most clients pick one of these; a few pick combinations.

### Renewal motion (months 10–12)

Annual license renewal happens at month 12. Spark Analytics begins the renewal conversation at month 10:

- Month 10: Renewal kickoff. Review usage, satisfaction, roadmap fit.
- Month 11: Renewal proposal delivered. Often includes expansion (additional modules, services).
- Month 12: Signature or non-renewal.

Renewal indicators (per §13.8) inform whether the conversation is celebratory or remedial.

### Expansion engagements

Clients adopting additional modules in v2 (Marketing Attribution, Customer Service, etc.) trigger 2–3 week add-on engagements, billed separately.

---

## 13.8 Operational metrics for Spark Analytics

Spark Analytics tracks per-client health metrics to manage the relationship proactively.

### Health score (composite, monthly)

| Dimension | Weight | Source |
|---|---|---|
| Data quality (test pass rate) | 25% | dbt test results |
| Source freshness compliance | 20% | Source freshness reports per Section 8.8 |
| Dashboard usage (% of dashboards opened weekly) | 20% | Power BI usage metrics |
| KPI accuracy (drift from expected values, where measurable) | 15% | Section 9.9 validation framework |
| Cost efficiency (Snowflake spend vs. baseline) | 10% | Section 4 Part 3 §4.46 cost monitoring |
| Support ticket volume and severity | 10% | Support system |

Each dimension is normalized 0–100; composite is a weighted average.

Score thresholds:

| Range | Interpretation | Action |
|---|---|---|
| 80–100 | Healthy | Standard cadence; reference-candidate |
| 60–79 | Watch | Monthly check-in by named TAM |
| 40–59 | At-risk | Engagement review; remediation plan |
| <40 | Crisis | Leadership intervention; renewal at risk |

### Adoption metrics (per dashboard)

| Metric | Healthy benchmark |
|---|---|
| % of named users who opened the dashboard last week | >60% |
| Median session duration | >2 minutes (less = "glance only," more = real exploration) |
| Filter changes per session | >2 (suggests active interrogation) |
| Drill-throughs per week | >10 (suggests genuine workflow integration) |

Adoption metrics combine into the dashboard usage component of health score.

### Renewal indicators

| Indicator | Direction |
|---|---|
| Decline in dashboard opens, 3+ months | ⚠️ |
| Decline in active analyst users | ⚠️ |
| Reduction in support tickets to zero (not by issue resolution but by disengagement) | ⚠️ |
| No new modules adopted in renewal window | ⚠️ |
| Executive sponsor leaves the company | ⚠️⚠️ |

Renewal indicators inform the month-10 renewal kickoff conversation; remediation begins at month 6 if indicators are flashing.

### Reference client management

Clients with sustained health scores ≥85 are flagged as reference candidates. Spark Analytics maintains a roster of ~5 reference clients per ICP segment (apparel D2C, beauty, home, etc.). Reference clients are asked for case studies, occasional sales calls, and conference speaking — never more than 3 hours quarterly.

---

## 13.9 Common operational issues and resolutions

The top issues that surface in client deployments, with their resolution patterns.

### Issue 1 — Source connector failures

| Symptom | Cause | Resolution |
|---|---|---|
| Source freshness alert: "Shopify has not received data in 24 hours" | Fivetran/Airbyte token expired, source API change, ingestion tool outage | Check ingestion tool dashboard first; if tool is healthy, refresh credentials; if API changed, check connector vendor's release notes |
| Specific table missing rows | Connector configuration excluded a field; source-side soft-delete | Compare row counts to source; check connector config |
| Schema drift error | Source added a new column not in pack's expected schema | Update mapping YAML to either consume or ignore the new column; never fail the pipeline |

### Issue 2 — Snowflake cost spikes

| Symptom | Cause | Resolution |
|---|---|---|
| Monthly Snowflake bill 2x normal | Inefficient query pattern, missing clustering key, warehouse not auto-suspending | Review `metadata.query_cost_log` (Section 4 Part 3 §4.46); identify top queries; add clustering or rewrite |
| Sudden spike on a specific day | One-off backfill, bulk reload, schema migration | Check `metadata.dbt_run_log` for unusual runs; if intentional, OK; if not, investigate |
| Steady creep over months | Data volume growth | Expected; revisit warehouse sizing quarterly per Section 4 Part 2 §4.30 capacity reference |

### Issue 3 — Slow dashboard loads

| Symptom | Cause | Resolution |
|---|---|---|
| Initial load >10 seconds | Power BI cache cold, large dataset, slow Snowflake response | Verify Power BI dataset has refreshed; check Snowflake warehouse size |
| Slicer change >5 seconds | DirectQuery mode active, complex DAX calculations, high-cardinality dimension | Switch to Import mode where possible; review DAX measures (most should live in semantic layer, not Power BI) |
| Drill-through >10 seconds | Drill-through filter pushing high-cardinality query | Review the drill-through target page; pre-aggregate if possible |

### Issue 4 — Customer identity resolution disputes

| Symptom | Cause | Resolution |
|---|---|---|
| "I see two customer records for one person I know" | Tier 3 fuzzy match didn't catch this case (per ADR-003) | Add manual override in `seeds/customer_identity_overrides.csv`; rerun build |
| "Two different people merged into one record" | False positive in Tier 3 fuzzy match | Same; manual override breaks the incorrect merge |
| Inflated active customer counts post-launch | Identity resolution running at default threshold; cleanup hasn't completed | Run the identity resolution backfill (per Section 4 Part 1 §4.3); expect 1-week stabilization |

### Issue 5 — Source-data quality regressions

| Symptom | Cause | Resolution |
|---|---|---|
| Sudden spike in failed tests on Shopify | Client changed something at source (new product type, new payment method, new channel) | Review failed test rows in quarantine; add accepted_values if legitimate new value; investigate if anomalous |
| GA4 events_count dropped 50% overnight | GA4 measurement code change at client site | Coordinate with client web team; pack tolerates the drop, but attribution will be affected |
| Klaviyo profiles missing email | Klaviyo allows email-less profiles; new consent flow may have introduced them | Update `dim_customer` source mapping to handle nulls; flag in identity resolution |

Each issue type has a runbook with detailed steps, owned by the support team and updated as new patterns emerge.

---

## 13.10 Client success playbook

The intervention patterns for clients whose adoption is on or off track.

### The 30/60/90 day milestone checks

| Milestone | What "healthy" looks like | What "struggling" looks like |
|---|---|---|
| **30 days** | At least 2 stakeholders viewing dashboards weekly; <5 P2+ support tickets open; first analyst-written ad-hoc query | No stakeholder using dashboards; many P1/P2 tickets; client team confused about where to find things |
| **60 days** | Dashboards used in actual business decisions; at least one custom slicer or filter added; minor questions only | Dashboards exist but aren't referenced in meetings; same questions keep coming from client; no extension or customization activity |
| **90 days** | Pack is "infrastructure" — taken for granted; client team owns most operational issues; conversation shifting to expansion | Pack still feels foreign; Spark Analytics still being asked basic operational questions; pre-pack reports still in use |

### Intervention when adoption stalls

If 30/60/90 indicators are negative, Spark Analytics initiates a structured intervention:

1. **Diagnostic week.** Engineering and product spend a week investigating: usage metrics, support patterns, dashboard quality. Find the root cause.
2. **Findings meeting.** Present to client with options. Common findings:
   - Dashboard doesn't show the metric they actually care about → fix or add
   - Stakeholder doesn't trust the numbers → reconcile to source data
   - Team doesn't know how to use it → re-do training
   - Wrong stakeholders trained → train the right ones
   - Original sales promise didn't match the product → reset expectations
3. **30-day improvement plan.** Concrete actions, owners, dates.
4. **Reassessment.** If improvement plan worked, return to standard cadence. If not, executive-level conversation about the engagement.

### Expansion conversation triggers

When a client is healthy (score ≥80), expansion is appropriate. Triggers:

| Trigger | Expansion conversation |
|---|---|
| Client asks about a metric not in pack | "We have a Pro KPI for that" or "That's a v2 feature" or "We could build that as a services engagement" |
| Client mentions a new business initiative | Map to relevant module — does it benefit from existing dashboards or warrant a custom page? |
| Renewal approaching | Standard pre-renewal conversation includes "what would v2 of our work together look like?" |
| Client hires more analysts | More analyst training; possibly Track 4 train-the-trainer |
| Client's GMV grows past their pricing tier | Pricing conversation; usually combined with feature expansion |

Expansion is **never aggressive**. The pattern is "you're already getting value here; would more value be useful?" — not "you should be buying more."

---

## 13.11 Documentation and knowledge management

Three documentation tiers, each with different access and update cadence.

### Tier 1 — Public documentation

| Audience | Anyone — OSS users, prospects, search engines |
|---|---|
| Location | GitHub repo README, docs site, dbt docs site |
| Contents | Installation, getting started, OSS feature documentation, API references, governance overview |
| Update cadence | Per release; community can submit PRs |
| Maintenance owner | Engineering lead + product |

### Tier 2 — Customer documentation

| Audience | Pro license clients |
|---|---|
| Location | Customer portal (separate auth) |
| Contents | Implementation playbook, full upgrade guides, advanced configuration, premium feature docs, recorded training sessions |
| Update cadence | Per release plus monthly review |
| Maintenance owner | Customer success + engineering |

### Tier 3 — Internal documentation

| Audience | Spark Analytics team only |
|---|---|
| Location | Internal wiki |
| Contents | Sales playbooks, support runbooks, internal incident logs, pricing details, customer-specific quirks, roadmap drafts |
| Update cadence | Continuous; weekly review by team leads |
| Maintenance owner | Each team for their area |

### Freshness review

Quarterly, all three tiers undergo a freshness audit:

- Any page not updated in 6 months → flagged for review
- Any page with negative user feedback → reviewed and fixed
- Any new product feature → corresponding docs in all relevant tiers

Stale documentation is more harmful than missing documentation. Honest "this page is being updated" is better than confidently wrong information.

---

## 13.12 Disaster recovery and business continuity

The pack's DR posture rests on three layers, two of which are Snowflake-native and one of which is dbt-native.

### Layer 1 — Snowflake Time Travel

Set to 7 days on `ANALYTICS_RETAIL` (per Section 2 §2.9). Any point-in-time query within the window is possible:

```sql
-- Query the warehouse as of 3 days ago
SELECT * FROM fact_orders AT(OFFSET => -86400 * 3);
```

This handles most "oops, we corrupted data with a bad build" scenarios. Recovery is instant.

### Layer 2 — Snowflake Fail-safe

Additional 7 days beyond Time Travel. Last-resort recovery via Snowflake support; not user-accessible directly. Handles catastrophic accidental data loss.

### Layer 3 — Git-backed dbt source code

The dbt project itself lives in Git. Any version of the transformation logic can be rebuilt from history. Combined with Time Travel, this enables full "rebuild yesterday's warehouse exactly as it was" capability.

### What is NOT in scope for v1 DR

- **Cross-region failover.** Snowflake's own multi-region replication can be enabled by the client; the pack doesn't configure it.
- **Active-active multi-account.** Out of scope.
- **Source system DR.** Shopify's availability is Shopify's problem; the pack is read-only consumer.

### Recovery objectives

| Scenario | RPO (data loss tolerance) | RTO (time to recover) |
|---|---|---|
| Bad dbt build corrupts marts | 0 (Time Travel restores instantly) | 15 minutes |
| Snowflake account-level issue | Snowflake's published SLA | Snowflake's published SLA |
| Loss of dbt Cloud (if Path 1) | 1 day (last successful build) | 1 day (rebuild from Git on dbt Core) |
| Loss of dbt source code | n/a (in Git) | 1 hour (re-clone repo) |
| Catastrophic Snowflake region loss | 24 hours (assuming Fail-safe is invocable) | 1–3 days (Snowflake support timeline) |

### Quarterly DR drills

For Managed Service clients, Spark Analytics runs a quarterly DR drill:

- Simulate a specific failure scenario (e.g., "yesterday's marts are corrupted")
- Execute the recovery procedure end-to-end
- Document the timing
- Update runbooks based on findings

Pro-license-only clients can request a DR drill as a one-time services engagement.

---

## 13.13 The end of v1

This section is the last section of the v1 design document. Beyond it, the document transitions from "design specification" to "living documentation" — release notes, post-mortems, ADRs for future decisions, and version-specific upgrades.

Three things signal that v1 design is genuinely done:

1. **Every Section 1.5 MVP scope item has a defining section.** Verified true across Sections 2–12.
2. **Every "deferred to v2" item is documented with the section that scoped it out.** Section 12.8 consolidates 27 such items.
3. **Every architectural decision has an ADR or section reference.** Verified true; ADR-004 closes the last open gap.

What remains beyond v1 design:

- The **build** itself, per Section 12's roadmap
- **First-client implementations**, per §13.2 and §13.7
- **The community** that forms around the OSS repo
- **The feedback loop** that informs v2

Everything that's not in this document is either implementation detail (which lives in code), commercial detail (which lives in contracts), or future evolution (which will be documented as it arrives).

---

## 13.14 Summary

Section 13 covers what happens after the pack is deployed — runbooks, support tiers, training, upgrades, engagement model, success metrics, common issues, documentation discipline, and disaster recovery.

Key operational decisions:

- **4–6 week implementation** is the standard engagement; phases align with quality gates
- **Six decisions at kickoff** define the deployment path (dbt Cloud vs. Core, currency, timezone, region, PII handling, retention)
- **Three support tiers** map to OSS / Pro / Managed Service
- **Four training tracks** address the spectrum from analysts to engineers to admins to trainers
- **Three upgrade patterns** for patch / minor / major releases — each self-serviceable at the appropriate complexity level
- **Five common operational issue categories** have documented runbooks
- **Three-tier documentation** model balances open access (public), client value (customer), and internal velocity (private)
- **Snowflake-native DR** for most scenarios; explicit RPO/RTO targets

This section also marks the end of v1 design. The 27 features deferred to v2 (per Section 12.8) and the implementation work ahead (per Section 12.4) define what comes next.

The pack is now fully specified. v1 build can begin.

---

**Previous:** [Section 12: Build Roadmap](./12_build_roadmap.md)
**Next:** *(end of v1 design document)*
