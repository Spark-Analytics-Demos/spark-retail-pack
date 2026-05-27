# Demo Script 3 — Pricing Churn

> **Audience:** CMO, VP Marketing, Head of CRM, Head of Customer Success
> **Duration:** 8–10 minutes
> **Story arc:** Story 3 — Sweater Pricing Change and Repeat Purchase Rate Dip (June–August 2026)
> **Best used for:** Marketing and retention-focused demos; leads who ask "what does this show about customer behavior?"

---

## Setup

Before the call:
- Open **Customer 360** dashboard
- Set date range: **April 1 – September 30, 2026**
- Have **Sales Analytics** open in a separate tab, filtered to **Tops → Sweaters**

---

## The Hook

> *"Every pricing team has had this conversation: 'we raised prices, revenue held flat, so the increase worked.' I want to show you what the data was actually saying — and why flat revenue is sometimes the worst possible signal."*

Pause. Let the Customer 360 dashboard render. The Repeat Purchase Rate chart will show a visible kink downward starting in late June.

---

## Walkthrough

### Step 1 — The pricing change and its cover (2 min)

**Screen:** Sales Analytics → Category Performance → Tops/Sweaters, April–August

Point to the monthly revenue bars for Sweaters:
- April average: **$148,000/month**
- June: **$151,000** — effectively flat after the 12% price increase on June 2
- Leadership reads: *pricing change neutral, hold.*

> *"On revenue alone, the June pricing change looks fine. Revenue is flat — which leadership interprets as 'price increase absorbed.' But flat revenue when you raised prices 12% means one thing: volume dropped to exactly offset the increase. You're doing the same dollar amount with fewer customers."*

Click into the unit volume view (not revenue):
- Sweater unit sales, May: **1,940 units**
- Sweater unit sales, July: **1,280 units** — a 34% volume decline
- The revenue flatness was masking a significant demand destruction

---

### Step 2 — The churn signal in Customer 360 (2 min)

**Screen:** Customer 360 → Retention tab → Repeat Purchase Rate

Point to the RPR trend line:
- May RPR: **28%** (pre-change baseline)
- July RPR: **22%** — a 6-percentage-point drop in 8 weeks
- September RPR: **26%** — partial recovery but not to baseline

> *"Repeat Purchase Rate is the metric that revenue can't hide behind. A customer who came back four times a year is now coming back three times. That's not in the revenue line for June — it shows up in the Q4 shortfall."*

Note: RPR is a lagging indicator by design. The pricing change happened June 2; RPR doesn't show the full impact until customers' next-expected-purchase dates pass without a return. The June cohort's repeat behavior becomes visible in July and August.

---

### Step 3 — Cohort-level evidence (2 min)

**Screen:** Customer 360 → Cohorts tab, June 2026 cohort vs. March 2026 cohort

Point to the cohort comparison:
- **March 2026 cohort** (pre-change): 30-day repeat rate **18%**, 90-day repeat rate **31%**
- **June 2026 cohort** (acquired during the price increase): 30-day repeat rate **12%**, 90-day repeat rate **22%**
- LTV projection at 12 months: March cohort **$310**, June cohort **$228** — a **$82 per-customer gap**

> *"This is where the story gets expensive. You're not just losing repeat purchases this quarter — you're acquiring a June cohort with structurally lower LTV. If you brought in 2,400 new customers in June, that's a potential $197,000 LTV haircut versus what a March acquisition would have been worth."*

---

### Step 4 — The email engagement confirmation (2 min)

**Screen:** Customer 360 → Email Engagement → Campaign-level view, June–August

Filter to Sweater-related campaigns:
- May average CTR on sweater campaigns: **4.2%**
- July average CTR on sweater campaigns: **2.8%** — a 33% drop
- Open rates held steady (~24%) — customers are still opening; they're just not clicking through to buy

> *"Open rates held — that tells you the relationship isn't broken. They still recognize the brand and open the email. But they're not clicking to buy. That gap between open and click is a price sensitivity signal. The list knows something the revenue line doesn't."*

Anticipate the challenge: *"Could this be seasonal — people just buy fewer sweaters in summer?"*
> *"Exactly the right challenge. Look at June 2025 — we don't have that year in the demo, but I can tell you the design: the generator applies the same seasonal multipliers both years. The summer dip is built into the baseline. The July 2026 drop is on top of the seasonal adjustment, not explained by it."*

---

## The "Aha" Moment

> *"Here's what this demo is actually showing you: revenue is a bad instrument for measuring pricing decisions. It's too aggregated, too slow, and too easy to interpret as 'good enough.' Repeat Purchase Rate and cohort LTV are the instruments that see the real effect 6–8 weeks earlier — and they're pointing in opposite directions from the revenue line.*
>
> *By September, Northwind's analytics team had the evidence to roll back 4 percentage points of the increase and retarget the June cohort specifically. The revenue chart didn't surface that. The Customer 360 did."*

---

## Questions to Expect

**"How do you separate pricing effect from seasonal effect?"**
> The pack uses year-over-year and category-indexed baselines. The seasonal multiplier for sweaters in July is computed from the full-year trend; a drop on top of that baseline is the anomaly. For this demo, the generator embeds the effect explicitly so the before/after is clean.

**"Does the pack tell us what the 'right' price is?"**
> No — price optimisation is a modelling problem outside the pack's scope. What the pack gives you is the behavioral signal fast enough to inform that decision. The insight is: "price change + repeat purchase drop = test a rollback." The decision is yours.

**"What if we don't have Klaviyo — can we still see email engagement?"**
> Email engagement (Step 4) requires the Klaviyo connector. Without it, you still get RPR and cohort LTV from Shopify order history alone — Steps 1–3 work without email data. Klaviyo adds the "why" layer.

**"Repeat Purchase Rate of 22% seems low — is that realistic for apparel?"**
> It's on the realistic end of typical D2C benchmarks for mid-market apparel, which range from 18–35% depending on price point and category. Higher-frequency categories (socks, basics) run higher; premium outerwear runs lower. Northwind's 28% baseline reflects a mixed catalog with strong loyalty in outerwear.

**"Can we see this at the individual customer level — which customers churned?"**
> Yes. The Customer 360 → At Risk view surfaces customers whose purchase gap has exceeded their segment's expected re-order window. The June cohort will surface prominently there by August. We can export that list as an audience segment for a win-back campaign directly from the dashboard.

---

## The Follow-Up Ask

> *"I'd like to show your CRM team the cohort drill-down in detail — there's a level of segmentation here that's hard to appreciate in a 10-minute overview. 30 minutes, focused on your current retention metrics. Would [day/time] work?"*

If they're already asking about their own data:
> *"The fastest path to seeing your own cohort curves is the POC. We connect to your Shopify order history — read-only, no production impact — and run the repeat purchase and LTV models against your real customer base. You'd see your June cohort behavior, your actual RPR trend, your at-risk segment list. Two weeks, no commitment."*

---

## Demo Notes

- The **12% Sweater price increase** is embedded in the generator and is not a dashboard control — you cannot show the pricing change being toggled in the demo. The story is told through behavioral consequences, not the price change itself.
- The **RPR values** (28% → 22% → 26%) are accurate for the Medium tier. Small tier RPR is slightly lower due to the reduced customer volume making the metric noisier — if demoing on Small, note the values may differ slightly.
- This demo works best as the **second demo** after the Black Friday script. The Black Friday demo shows upside; the Pricing Churn demo shows the diagnostic use case. Together they cover both the "celebration" and "investigation" modes of analytics.
- If the prospect's business is not apparel, swap the Sweater story for "the equivalent mid-tier category in your catalog that has some pricing flexibility." The mechanism is identical regardless of product type.
- The cohort LTV numbers ($310 vs. $228) should be framed as the pack's projections using historical repeat rates, not guaranteed future values. Say "projected" not "will."
