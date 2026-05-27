# Demo Script 4 — Viral Moment

> **Audience:** CMO, VP Marketing, Head of Growth, Head of Performance Marketing
> **Duration:** 8–10 minutes
> **Story arc:** Story 4 — Cargo Field Pants Viral Spike (September 14–28, 2026)
> **Best used for:** Marketing-led demos; leads who ask "how does this help us capture and understand demand surges?"

---

## Setup

Before the call:
- Open **Customer 360** dashboard
- Set date range: **August 1 – October 15, 2026**
- Have **Sales Analytics** open in a separate tab, filtered to **Bottoms → Pants**
- Have **Inventory Health** open in a third tab, filtered to SKU `BP-001-REG-KHA`

---

## The Hook

> *"A 280,000-follower influencer posted an unboxing video on September 14th. Northwind's team didn't know it was coming. I want to show you what that looked like in the data — and what a team with this dashboard knew by September 16th that a team without it wouldn't figure out until the October marketing review."*

Pause. Let the Customer 360 dashboard load. The daily new customer acquisition chart will show a near-vertical line starting September 14.

---

## Walkthrough

### Step 1 — The acquisition spike (2 min)

**Screen:** Customer 360 → Acquisition tab, daily new customers

Point to the chart:
- August baseline: **~70 new customers per day**
- September 14: **487 new customers**
- September 15: **612 new customers** — peak day
- September 16: **594 new customers**
- The elevated rate persists through September 28 before fading back to baseline

Full month of September: **7,438 new customers** vs. the ~2,500 monthly typical — a **3× month**

> *"612 new customers in a single day from a brand with no paid push on that day. That's the viral coefficient — a signal you can only see this fast if your acquisition data is live, not batched."*

Click to the channel breakdown for September 14–28:
- **Referral and Direct** together: 71% of September new customer acquisition
- **Meta** share drops from 38% to 18% — not because Meta declined, but because everything else grew disproportionately
- This is the fingerprint of untracked organic growth

> *"When Referral and Direct spike together and Meta's share drops, that's almost always a viral or PR event. The tool can't tell you it was an influencer — but it can tell you something happened that isn't in your paid media plan, and it happened on September 14th."*

---

### Step 2 — The SKU-level revenue signal (2 min)

**Screen:** Sales Analytics → Product Performance → Bottoms/Pants, September

Point to the SKU ranking:
- `BP-001-REG-KHA` (Cargo Field Pants — Regular — Khaki): **#1 SKU for the month** by revenue
- September revenue from this SKU: **$218,400**
- August revenue from the same SKU: **$14,700**
- That's a **14.8× individual SKU spike** within a single calendar month

> *"This is the SKU that caused the acquisition spike — not the other way around. The influencer featured this specific product. The revenue attribution points to Cargo Field Pants as the epicentre before anyone on the team has watched the video."*

Point to the broader Bottoms/Pants category trend:
- The rest of the Pants subcategory is essentially flat during this period
- The spike is concentrated in a single SKU and its nearest variants (Olive and Charcoal colorways also spike, though less dramatically)

---

### Step 3 — Inventory impact and the missed opportunity (2 min)

**Screen:** Inventory Health → SKU detail for `BP-001-REG-KHA`

Show the inventory depletion:
- Stock on September 13 (day before the video): **534 units**
- Daily velocity September 14–21: **~62 units/day** vs. ~2 units/day pre-viral
- Stock hits zero: **September 22** — 8 days after the viral event begins
- Restock arrival: **October 8** — a 16-day gap at zero

> *"534 units sounded fine before September 14th. 8 days later it's gone. The reorder flag fired on September 17th — but with an 18-day supplier lead time, there was no catching up. This is the difference between the pack surfacing the alert and the system being able to do something about it: sometimes the physics of supply chain just lose."*

Show the Inventory at Risk panel for September 18:
- `BP-001-REG-KHA`: Days of Supply **4**, velocity **62/day**, reorder recommended
- The alert fired on schedule — the lead time couldn't close the gap

> *"The learning here isn't 'the dashboard didn't save us.' The learning is: when Referral/Direct spikes on September 14th, the ops team needs to be looking at the top acquisition SKUs that same day — not the inventory alert on September 17th. That's a process question the data now makes possible to ask."*

---

### Step 4 — CAC and ROAS in the aftermath (2 min)

**Screen:** Customer 360 → CAC by Channel, September view

Point to the blended CAC:
- August blended CAC: **$58** (typical)
- September blended CAC: **$31**

> *"CAC drops to $31 because you're attributing 7,438 new customers against a Meta budget that didn't change. The denominator exploded without the numerator moving. That's what organic viral spillover looks like in acquisition metrics — it makes your paid channels look more efficient than they are."*

Anticipate the question: *"So ROAS is misleading in September?"*
> *"Exactly. September ROAS on Meta looks fantastic — but it's riding an organic wave, not a paid optimization. The pack shows you both views: blended CAC (which collapses this) and channel-isolated CAC (which lets you see Meta's actual contribution). The risk is optimising paid spend in October based on September's blended ROAS — you'd be chasing a signal that's already gone."*

---

## The "Aha" Moment

> *"By September 16th — 48 hours after the video — Northwind's team had three data points they couldn't have assembled in under a week without this dashboard: (1) a specific SKU caused a viral acquisition spike, (2) that SKU had 8 days of stock left at current velocity, (3) the CAC figures for the month were going to look misleadingly good.*
>
> *None of that required an analyst to run a query. The CMO opened the dashboard on Tuesday morning, saw the channel breakdown, and asked the inventory question before the ops meeting. That's not a data team win — that's a business tempo shift."*

---

## Questions to Expect

**"Can the pack identify the influencer post specifically?"**
> No — attribution at the individual-content-creator level requires a social listening tool (Sprout Social, Mention, etc.) that isn't in the connector set. The pack identifies the timing and channel pattern of the organic surge; connecting it to a specific post is a human inference step, usually a 5-minute search once you know the date.

**"How does it know the spike was from Referral vs. Direct?"**
> Source attribution uses UTM parameters on inbound sessions from the GA4 connector, combined with Shopify's referral source field on orders. The channel split is as accurate as the UTM coverage — typically 85–90% tagged for paid channels, with the untagged remainder landing in Direct. A viral post often lacks UTMs, so Direct is elevated. That pattern (Referral + Direct spike with no corresponding paid increase) is the tell.

**"What if we want to build a rapid-response process for viral events?"**
> The pack doesn't include workflow automation, but the Inventory at Risk alert is designed to feed into ops systems via export. The recommended setup is a Slack notification from Snowflake when any SKU crosses the 5-day supply threshold during a high-velocity period — that's an ops configuration, not a pack feature, but we document the setup in the implementation playbook.

**"Can we see which new customers from the viral spike became repeat buyers?"**
> Yes — the September 2026 acquisition cohort in Customer 360 → Cohorts will show the repeat rate at 30, 60, and 90 days. Viral-driven cohorts often have above-average repeat rates because they're product-motivated acquirers, not discount hunters. Check it in late November. In the demo data, this cohort's 90-day repeat rate is one of the strongest in the year.

**"What about TikTok or Instagram Reels — does the pack capture those channels?"**
> Meta (Instagram + Facebook) is the primary connector for paid social. Organic TikTok and Reels engagement isn't directly ingested in v1 — it surfaces in the Referral/Direct signal when it drives sessions, not as a tagged channel. Adding TikTok as a distinct channel source is a v2 roadmap item.

---

## The Follow-Up Ask

> *"I'd like to show your growth team the channel decomposition in more detail — there's a paid vs. organic attribution view that takes 15 minutes to walk through properly and tends to generate a lot of questions. Would [day/time] work for a follow-on session?"*

If they're marketing-analytics-sophisticated:
> *"The most valuable thing we could do is run your September against this model. If you had an organic spike event in the last 12 months, we could show you what the channel fingerprint looked like, what your SKU-level signal was, and what the CAC distortion was. That's a 2-week POC on your own Shopify data. Want to scope it?"*

---

## Demo Notes

- `BP-001-REG-KHA` is the canonical SKU identifier in the dataset. In the demo UI it renders as "Cargo Field Pants — Regular Fit — Khaki." Olive (`BP-001-REG-OLV`) and Charcoal (`BP-001-REG-CHA`) variants show secondary spikes.
- The **~600 new customers/day peak** (September 15: 612) is accurate for Medium tier. Small tier will show a lower absolute number but the same proportional shape — calibrate your language accordingly.
- The **CAC drop to $31** is specific to the September blended figure. If asked to drill into Meta-only CAC in September, the Meta-attributed CAC is higher ($48) because Meta's actual spend-to-attributed-acquisition ratio didn't change — the blended figure is diluted by organic volume.
- This script works best for marketing leads who are already CAC/ROAS-literate. If the prospect is more operational, lean into Steps 2–3 (SKU-level signal and inventory consequence) and skip or shorten Step 4.
- The 16-day stockout (Sep 22 – Oct 8) is a sympathetic failure case, not a critical failure of the pack. Frame it as: "the alert was correct and timely; the supply chain physics were unwinnable." This prevents the prospect from reading the demo as "the tool didn't prevent the problem."
