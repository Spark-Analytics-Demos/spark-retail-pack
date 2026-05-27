# Demo Script 1 — Black Friday Spike

> **Audience:** CEO, Head of Finance, VP Revenue
> **Duration:** 8–10 minutes
> **Story arc:** Story 1 — Black Friday (November 28–December 1, 2026)
> **Best used for:** Executive-level first demos; leads who ask "what does the pack actually show?"

---

## Setup

Before the call:
- Open **Executive Summary** dashboard
- Set date range: **November 1 – December 15, 2026**
- Have **Customer 360** and **Inventory Health** open in separate browser tabs

---

## The Hook

> *"Most finance teams find out what happened in Black Friday on the December close call. Let me show you what a team running Spark Retail Pack knows by December 3rd — and what they're already acting on."*

Pause. Let the dashboard load. Don't click anything yet — the daily revenue chart alone will prompt questions.

---

## Walkthrough

### Step 1 — The spike (2 min)

**Screen:** Executive Summary → Daily GMV chart, November

Point to the chart:
- The flat baseline: ~$66K average daily revenue through most of November
- The vertical spike: November 28–29 peak at **$543K** — that's **8.2× the November daily average**
- The extended tail: December 1 (Cyber Monday) still at **7.1×** before the curve breaks downward

Call out:
> *"Four days. $1.8M incremental revenue. This is what Black Friday looks like in clean data."*

Click on **November 29** (Black Friday itself):
- **Order count: 3,847** orders in a single day vs. ~330 average
- **AOV: $98** vs. $207 monthly average — discount-driven, completely expected
- **Discount application rate: 92%** of orders carried a promotional code

> *"The AOV drop isn't a problem — it's expected. The question is whether the margin on those 3,847 orders was worth the promotional spend. The pack answers that before the CFO asks."*

---

### Step 2 — Customer acquisition (2 min)

**Screen:** Switch to Customer 360 → Acquisition tab

Point to the new customer line:
- Typical day: **~70 new customers**
- November 29: **1,402 new customers in a single day**
- These are real new-to-brand buyers, not returning customers with a new email

Point to CAC:
- September average CAC: **$73** (paid channels)
- November 28–December 1 blended CAC: **$42**

> *"CAC dropped $31 because organic search, referral, and direct traffic all spiked alongside Meta. The same ad spend acquired more customers — that's ROAS as it's actually supposed to be measured, not just on paid."*

Anticipate the question: *"Is that sustainable?"*
> *"No — and that's the point. This spike gives you a baseline for what untapped demand looks like. The customers who came in organically during Black Friday are often your best cohort — higher repeat rates, lower acquisition cost. Let me show you that in a moment."*

---

### Step 3 — Inventory impact (2 min)

**Screen:** Switch to Inventory Health → Out of Stock view, December 2

Point to the stockout list:
- **78 SKUs** at zero available stock by December 2
- **Limited Editions** subcategory: **95% sell-through in 4 days**
- **Inventory at Risk** panel: $340K of stock below 14-day supply threshold

> *"The inventory team knew by December 2 that 78 SKUs needed emergency reorder. Without this dashboard, that's a December 20 call from the warehouse."*

Click into a specific stockout SKU (Limited Edition category, highest velocity):
- Show the inventory trend: sharp slope down starting November 28
- Days of Supply: 0
- The reorder flag has already fired

> *"This is the alert that goes to the ops team, not the CEO. The CEO sees the revenue number; the ops team sees the 78 SKU alert and makes the call before stock-outs affect January."*

---

### Step 4 — The forward signal (2 min)

**Screen:** Executive Summary → Refunds widget, December 1–15 view; then extend to January 2027

Point to the refund trend line emerging in early January:
- Refund volume beginning to climb: typically **4× the normal daily rate** starting mid-January
- This is the post-holiday return curve beginning to form

> *"The pack is already seeing January. Post-holiday returns for Black Friday orders typically peak 6–8 weeks out. The finance team can accrue correctly for December close — before a single customer has shipped anything back."*

---

## The "Aha" Moment

> *"Notice what didn't happen here. No one exported to Excel. No one ran a SQL query. No one asked the data team to 'pull the Black Friday numbers.' The CEO opened a browser on December 3rd and saw this.*
>
> *That's not a technical achievement — that's a business capability. The difference between a company that reviews Black Friday in February and one that acts on it by December 5th is usually worth more than the cost of the tool."*

---

## Questions to Expect

**"How quickly could we get this running on our data?"**
> 4–6 weeks from signed agreement to live dashboards. Week 1: infrastructure. Week 2: connectors. Weeks 3–4: dbt build and validation. Week 5: dashboards. Week 6: your team signs off. See the implementation playbook for the full timeline.

**"What if our Black Friday looks different from Northwind's?"**
> The story arc is parameterised — Northwind's 8× multiplier is configurable. But more importantly: the pack will show *your* Black Friday, not Northwind's. This is synthetic demo data. Your data replaces it on day one.

**"Does this work with Shopify Plus / a headless storefront / [other platform]?"**
> Shopify is the primary connector — both standard and Plus. For headless storefronts, the pack ingests from Shopify's order API regardless of frontend. Non-Shopify systems are a connector conversation for the technical team.

**"What about the refund data — is that from Stripe or Shopify?"**
> Both. The pack joins Shopify refunds (the authorisation) with Stripe refunds (the payment movement). You get a single refund fact table with both views reconciled. Discrepancies between Shopify and Stripe are flagged automatically.

**"Can we see our own data before we commit?"**
> Yes. The evaluation path is: (1) clone the OSS repo and run the demo data generator locally in under 15 minutes, (2) book a live demo on our hosted environment with Northwind data, (3) sign and we connect to your Shopify/Stripe. Most clients pick option 2 first.

---

## The Follow-Up Ask

> *"I'd like to propose a technical deep-dive with your analytics engineer — 45 minutes, we walk through the dbt models and show exactly how the revenue numbers in that chart are computed. Would [day/time] work?"*

If they're ready to move faster:
> *"We can scope a proof of concept — we connect to your Shopify sandbox data, build the first three staging models, and you see your own numbers in this dashboard within two weeks. No production data required for the POC."*

---

## Demo Notes

- The **November 29 peak value of $543K** is specific to Northwind's medium-tier dataset (seed=42, 120K orders/year). If running on the large tier, this figure is approximately 5× higher. Calibrate your language to whichever environment you're demoing.
- The **78 SKU stockout count** is most dramatic at the end of Cyber Monday (December 1). The exact count varies slightly with tier.
- If the prospect interrupts during the inventory step to ask about a specific SKU — let them explore. The ability to drill down to a single SKU is a demo moment in itself.
- Do not demo the January refund signal if the prospect seems overwhelmed. It's a second-order insight best suited for finance-sophisticated audiences.
