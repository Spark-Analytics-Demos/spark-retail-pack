# Demo Script 5 — Resort Wear Flop

> **Audience:** Head of Merchandising, VP Product, Head of Buying, CFO
> **Duration:** 8–10 minutes
> **Story arc:** Story 5 — Resort Wear Capsule Failure (March–May 2026)
> **Best used for:** Merchandising and buying-focused demos; leads who ask "how does this help us manage a product launch?"

---

## Setup

Before the call:
- Open **Inventory Health** dashboard
- Set date range: **February 15 – June 15, 2026**
- Filter the **Inventory at Risk** panel to subcategory: **Resort Wear**
- Have **Sales Analytics** open in a separate tab, filtered to **Resort Wear**

---

## The Hook

> *"Every buying team has launched something that didn't land. The question isn't whether it happens — it's how long you carry the problem before you act on it. I want to show you what 7 weeks of hesitation looks like in inventory value, and what cutting it at 3 weeks instead would have meant."*

Pause. Let the Inventory Health dashboard render. The Resort Wear Sell-Through Rate chart will show a flat line well below the category baseline.

---

## Walkthrough

### Step 1 — The launch and the early warning (2 min)

**Screen:** Inventory Health → New Launch Tracker, March 1

Point to the Resort Wear capsule on the launch tracker:
- **18 SKUs** across Swimwear, Linen Sets, and Sandals launched **March 1, 2026**
- Opening stock: ~**3,200 units** across the line, valued at **$284,000**
- Expected 30-day sell-through for a new launch: ~**60%**

Click to the **14-day post-launch view** (March 15):
- Actual 14-day sell-through: **11%**
- Expected 14-day sell-through: ~30%
- The Sell-Through Rate alert fires on **March 12** — 11 days after launch

> *"The alert fired on March 12th. Eleven days into a product launch, the system had already identified this line as underperforming against its expected trajectory. At that point, 89% of inventory was still in the warehouse."*

---

### Step 2 — The slow-mover cascade (2 min)

**Screen:** Inventory Health → Slow Movers panel, April 15

Point to the slow-mover list:
- By April 15: **14 of 18** Resort Wear SKUs flagged as slow-movers
- **Sell-through at 45 days: 22%** vs. the 60% expected for a new launch
- The 4 SKUs not yet flagged: Sandals variants (they're benefiting from moderate spring traffic)

Point to the **Inventory Value at Risk** number:
- Resort Wear inventory still on-hand as of April 15: **$221,000** of the original $284,000
- That's $221,000 sitting in the warehouse at full cost, generating no revenue

> *"$221,000 at 45 days. For context: at the expected 60% sell-through for a new launch, you'd have cleared $170,000 of that by now. Instead only $63,000 has moved. The $107,000 shortfall from expected demand isn't recoverable — and every day it doesn't move, the markdown you'll eventually take gets larger."*

---

### Step 3 — The cost of waiting (2 min)

**Screen:** Sales Analytics → Category Performance → Resort Wear, March–May

Show the weekly revenue bars:
- Week of March 1 (launch): **$8,400** — modest but expected for week 1
- Week of March 15: **$3,200** — declining, not ramping
- Week of April 15: **$1,800** — essentially flat at a low level
- Week of May 15 (post-clearance): **$6,200** — the clearance markdown drove a temporary lift

Point to the clearance event on May 15:
- Northwind moved Resort Wear to **30% off** on May 15
- Clearance sell-through over the following 3 weeks: **full remaining stock moved**
- The 30% markdown means: **$0.70 per dollar of inventory recovered**

> *"The clearance decision on May 15th was the right call — but it came 10 weeks after the system first signalled underperformance. By May 15th, 78% of the inventory value was still in the building at full cost. At 30% off, you recovered roughly $154,000 of the $221,000 you'd been holding. That's a $67,000 markdown loss on a line that an earlier decision would have cleared faster and cheaper."*

---

### Step 4 — The counterfactual (2 min)

**Screen:** Inventory Health → Scenario view (or narrate if dashboard doesn't support interactive scenario)

Walk through the "what if" scenario:
- **Actual timeline:** First alert March 12 → clearance decision May 15 → 63-day wait
- **Accelerated timeline:** Clearance on March 28 (16 days after first alert)
  - Remaining inventory at March 28: ~$257,000 (only 11% sold through)
  - 30% markdown applied 47 days earlier
  - Earlier markdown typically drives faster sell-through (seasonal momentum still active in late March)
  - Estimated recovery at 20% markdown in late March vs. 30% markdown in mid-May: **meaningful difference**

> *"The data doesn't make the clearance decision for you — there are legitimate business reasons to wait (brand positioning, seasonal timing, sell-in expectations). But it gives you the signal early enough that the decision is a choice, not a reaction. On May 15th, markdown was inevitable. On March 28th, it was still a strategy."*

---

## The "Aha" Moment

> *"What this demo shows isn't a failure of the buying team. They made a reasonable call on a spring line. What it shows is the difference between discovering underperformance on the March 12th alert vs. the April 20th buying review.*
>
> *Eight weeks. That's how long the data was pointing one direction while the calendar was pointing another. The pack compresses that gap — not to zero, but from 8 weeks to 11 days. The financial consequence of that compression, across a product catalog with two or three underperformers per season, is meaningful."*

---

## Questions to Expect

**"How does the pack know what 'expected sell-through' is for a new launch?"**
> The expected sell-through baseline is configurable per category and launch type, set in `seeds/sell_through_benchmarks.csv` during implementation. Defaults are derived from industry benchmarks (60% at 30 days for fashion apparel); you can override per subcategory with your own historical data. The alert fires when actual vs. expected drops below a configurable threshold (default: 50% of expected).

**"Can it differentiate between 'wrong product' and 'wrong price'?"**
> Not directly — the pack surfaces the symptom (slow sell-through) but the diagnosis requires human context. What it gives you is the evidence to have that conversation at week 2 instead of week 10: "Is this a price problem? A placement problem? A size run problem?" The data gets you to the question faster; the answer is still yours.

**"What about products that are supposed to be slow — premium items, made-to-order?"**
> The slow-mover logic is configurable per SKU and category. SKUs tagged as premium or limited-availability have different velocity expectations in the seeds config. You'd typically exclude made-to-order from the slow-mover scan entirely. This is an implementation-time configuration, not a limitation of the model.

**"Does the pack support markdown optimisation — calculating the optimal discount?"**
> No — markdown optimisation is a pricing science problem outside the pack's scope. The pack surfaces the sell-through signal and the inventory-at-risk value; the markdown decision (how much, when) is yours. If you have a pricing tool, the pack's inventory data can feed into it — the `fact_inventory_snapshot` table is the right source.

**"Can we see this at the colour/size variant level?"**
> Yes. The slow-mover flag and sell-through rate are computed at the SKU variant level (the product-colour-size combination). In the Resort Wear demo, you can drill into which specific size runs are moving vs. stagnant — sometimes a product is only slow in one size, and the reorder or markdown decision needs to be at that level.

---

## The Follow-Up Ask

> *"For merchandising teams, the most compelling next step is usually a category audit — running your current seasonal inventory through the slow-mover model and seeing which lines are already at risk. That takes two weeks on your Shopify data and requires no production access beyond read-only. Want to scope that as a starting point?"*

If the CFO is on the call:
> *"From a working capital perspective, the question worth modelling is: if we had 30-day vs. 10-day visibility on underperforming launches, what does that do to inventory turnover and markdown loss over a full year? That's a back-of-envelope calculation I'm happy to walk through with your finance team — it tends to be the clearest ROI framing for this kind of tool."*

---

## Demo Notes

- Resort Wear is a **subcategory**, not a top-level category — in the navigation it appears under a parent category. In the demo UI it's visible as a filter in both Inventory Health and Sales Analytics.
- The **18 SKU count** is exact in the Medium tier. In the Small tier, the number is proportionally reduced; use "approximately 10 SKUs" if demoing on Small.
- The **22% sell-through at 30 days** is the headline number. Some audiences respond better to the absolute dollar framing ("$221,000 sitting in the warehouse at 45 days") — read the room and lead with whichever resonates.
- The **counterfactual (Step 4)** is the most cognitively demanding part of this script. If the audience is not analytically minded, condense it to one sentence: "If the team had acted on the March 12th alert rather than the April 20th review, they'd have started clearing inventory 39 days earlier, in a warmer market, at a lower markdown rate." Then move to the Aha Moment.
- This script works best paired with Script 2 (Inventory Crisis) for operations-focused audiences — one story is about stockout (demand > supply), the other is about overstock (supply > demand). Together they show the pack covers both failure modes.
- Avoid the phrase "the buying team made a mistake." The framing is always "the data gave them earlier signal" — the decision-making is respected, only the timing is the variable.
