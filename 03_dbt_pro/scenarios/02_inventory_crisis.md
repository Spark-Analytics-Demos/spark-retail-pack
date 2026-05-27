# Demo Script 2 — Inventory Crisis

> **Audience:** COO, VP Operations, Head of Merchandising, Demand Planning Lead
> **Duration:** 8–10 minutes
> **Story arc:** Story 2 — Heritage Denim Jacket Stockout (April 8–25, 2026)
> **Best used for:** Operations and inventory-focused demos; leads who ask "what does this do for stock management?"

---

## Setup

Before the call:
- Open **Inventory Health** dashboard
- Set date range: **March 15 – May 10, 2026**
- Have **Sales Analytics** open in a separate browser tab, filtered to **Outerwear → Jackets**

---

## The Hook

> *"I want to show you what $180,000 of lost revenue looks like in data — and more importantly, what it looks like before it happens. This is the kind of visibility that turns a warehouse call on April 25th into an action on April 6th."*

Pause. Let the Inventory Health dashboard load. The chart for `HJ-001-MED-BLU` (Heritage Denim Jacket, Medium, Blue) will show a sharp slope to zero.

---

## Walkthrough

### Step 1 — The stockout (2 min)

**Screen:** Inventory Health → Days of Supply view, April 8

Point to the trend line:
- `HJ-001-MED-BLU` is Northwind's #1 revenue SKU — $420K GMV in Q1 2026
- The **reorder threshold** is 14 days of supply — this SKU crossed it on **March 28**
- On April 8: stock reaches zero. The stockout flag fires.

> *"The threshold breach was March 28. The stockout was April 8. An order placed the day the alert fired would have arrived April 15 — cutting the 17-day stockout to 7 days. The question isn't whether the alert fired — it's whether someone acted on it."*

Click into the SKU detail:
- Initial stock: 847 units
- Daily velocity in late March: ~48 units/day (spring fashion week mention driving demand)
- Restock arrival: **April 26** — a 17-day gap at zero

---

### Step 2 — The revenue impact (2 min)

**Screen:** Switch to Sales Analytics → Category Performance → Outerwear/Jackets, March 15–May 10

Point to the category revenue line:
- March average daily revenue, Jackets: **$14,200**
- April 9–25 daily revenue, Jackets: **$3,800** — a drop of ~73%
- That's not a market shift. That's one SKU going dark.

> *"$180,000 in estimated lost Jacket revenue across 17 days. That's the conservative estimate — it doesn't count the customers who searched for the jacket, didn't find it, and went to a competitor. That's demand leakage with no data trail."*

Point to the recovery:
- April 26 (restock day): revenue rebounds to **$16,400** — above pre-stockout levels
- That one-day spike is the suppressed demand releasing. It confirms the stockout was demand-driven, not market-driven.

---

### Step 3 — What the system saw in advance (2 min)

**Screen:** Back to Inventory Health → Inventory at Risk panel, April 1

Scroll to the **Inventory at Risk** list:
- `HJ-001-MED-BLU` appears on **March 28** — the day the 14-day threshold was crossed
- Days of Supply: **14** (exactly at threshold)
- The alert status: **reorder recommended**

> *"This is not a hindsight feature. On April 1st, if someone had opened this dashboard, they would have seen HJ-001-MED-BLU with 7 days of supply and a reorder flag that had been firing for four days. The supplier lead time is 18 days — the math to fully prevent the stockout no longer worked. But acting on April 1st would have cut the 17-day gap to 10 days."*

Anticipate the question: *"So why wasn't it actioned?"*
> *"That's the right question — and it's an operations question, not a data question. But without this dashboard, the question doesn't get asked until April 25th. With it, it gets asked on April 1st. That's the shift."*

---

### Step 4 — The downstream customer signal (2 min)

**Screen:** Customer 360 → Email Engagement tab, April 20–30

Point to the "back in stock" notification spike:
- Northwind sent back-in-stock emails for `HJ-001-MED-BLU` on **April 26**
- Open rate: **61%** vs. 24% campaign average
- Click-through rate: **18%** vs. 4.2% campaign average
- Conversion to purchase within 48 hours: **~32%** of clickers

> *"61% open rate on a back-in-stock notification. That email list existed because customers tried to buy the jacket, hit the out-of-stock page, and opted in. That waitlist is suppressed demand made visible — and it confirms $180K is conservative, not generous."*

---

## The "Aha" Moment

> *"Here's what changed with this dashboard: the conversation moved from 'how did we run out?' to 'how did the alert not get acted on?' That's a completely different conversation. One leads to a post-mortem. The other leads to a process change.*
>
> *The data was there. The threshold was set correctly. The reorder flag fired on time. What the pack gives you is the ability to say that with confidence — instead of spending two weeks trying to figure out whether the system even knew."*

---

## Questions to Expect

**"How does it know what the reorder threshold should be?"**
> The pack uses a configurable days-of-supply threshold (default: 14 days, adjustable per SKU or category). It doesn't auto-set the threshold — that's your team's call. But it does surface every SKU that's crossed it, ranked by revenue impact, every day.

**"Can it auto-trigger a PO?"**
> Not in v1 — the pack surfaces the alert and the data, not the workflow automation. But the Inventory at Risk export is designed to feed into Cin7, Brightpearl, or whatever your reorder workflow is. The pack tells you what; your ops system does what next.

**"What if we have multiple warehouses?"**
> The Medium tier demos a single Portland warehouse — Northwind is single-location in v1. Multi-location inventory is a v2 feature. For clients with 2–3 locations, we build the aggregate view into the core model; per-location drill-down is roadmapped.

**"How accurate is the $180K lost revenue estimate?"**
> It's derived from the SKU's trailing 30-day daily velocity × days at zero stock, which is the standard approach. It deliberately understates true impact because it doesn't count demand leakage (customers who went elsewhere and never came back). The real number is higher.

**"Can we see supplier lead time data in the dashboard?"**
> Supplier lead time is a configurable seed (`seeds/supplier_lead_times.csv` in the OSS package). For the demo, it's set to 18 days for this SKU. If your team has lead time data in a spreadsheet or ERP, we ingest it in Week 2 of the implementation.

---

## The Follow-Up Ask

> *"I'd like to set up a 45-minute session with your head of inventory and your analytics engineer. We'd walk through how the days-of-supply calculation is parameterised and show exactly what the reorder alert looks like on your actual SKU list. Would [day/time] work?"*

If they're ready to move faster:
> *"We can scope a proof of concept specifically on your top 50 revenue SKUs. Connect to your Shopify or your ERP export, run the stockout risk model, and show you which SKUs are currently within 14 days of zero — without going anywhere near production data. Two weeks, no risk."*

---

## Demo Notes

- `HJ-001-MED-BLU` is the correct SKU identifier in the demo dataset. The full product name in the catalog is "Heritage Denim Jacket — Medium — Indigo Blue." The demo UI shows the SKU code in the drill-down and the full name in the product card.
- The **$180K lost revenue figure** is best stated as "approximately" — the exact number varies slightly with tier and generation seed.
- The **back-in-stock email spike** (Step 4) is optional if time is short. It plays best with marketing-minded audiences who are already thinking about retention.
- If the prospect has a Klaviyo account, mention that the email engagement data in Step 4 comes directly from the Klaviyo connector — this is real-connector data, not modeled estimates.
- Avoid the phrase "the system would have caught this" — it's technically accurate but implies the human didn't need to be in the loop. The pitch is "the data made it visible"; the decision was always the team's.
