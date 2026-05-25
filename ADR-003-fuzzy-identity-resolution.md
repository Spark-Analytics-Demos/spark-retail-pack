# ADR-003: Fuzzy Identity Resolution

**Status:** Accepted
**Date:** 2026-05-13
**Deciders:** Spark Analytics leadership
**Supersedes:** N/A
**Superseded by:** N/A

---

## Context

The Spark Retail Pack resolves customer identities across multiple source systems (Shopify, Stripe, Klaviyo) into a single canonical customer record in `dim_customer`. The initial design (Section 4 Part 1) used a two-tier approach: deterministic email match (Tier 1) and deterministic phone match (Tier 2). Fuzzy name+address matching was deferred to v2.

During design review, this was challenged. The deferral assumed false positives from fuzzy matching outweighed the cost of unmatched customers — but real-world retail data tells a different story:

- Customers routinely use different emails across systems (work email on Shopify, personal email on Klaviyo)
- Email addresses change (job changes, marriage, new domains)
- Phone numbers are often missing in one or more systems
- The same customer may appear as "Bob Smith", "Robert Smith", and "Rob Smith" across sources

A two-tier-only approach leaves these as **separate customers** in the warehouse, inflating customer counts, depressing LTV calculations, and breaking retention analysis. For mid-market D2C clients, the unmatched rate with email-only matching can be 15–25% — material enough to make several key KPIs unreliable.

The question is not whether to add fuzzy matching, but how to add it without erosion of trust from false positives.

---

## Options considered

### Option A: Defer fuzzy matching to v2 (original design)

Only email and phone deterministic matching in v1.

**Pros:** Simple. No false-positive risk.
**Cons:** 15–25% of customers remain unmatched in typical mid-market data. Breaks core KPIs (LTV, retention, repeat rate). Forces clients to accept inflated customer counts or to build matching themselves.

### Option B: Aggressive fuzzy matching (name only)

Match on normalized name similarity, no other constraints.

**Pros:** Maximum matching coverage.
**Cons:** Catastrophic false positives. Two different "John Smith"s become one customer. Erodes data trust beyond recovery — once a client sees a wrong merge, they distrust the entire warehouse.

### Option C: Tiered fuzzy matching with confidence flags

Three tiers: email (high confidence) → phone (high confidence) → fuzzy name+address (medium confidence). Each match is flagged with its method and confidence level. Clients can override via configuration.

**Pros:** Catches the real-world variability. Confidence flagging preserves trust — analysts know which records to scrutinize. Override mechanism puts clients in control.
**Cons:** More complex to implement. Requires a manual review workflow for medium-confidence matches.

### Option D: Probabilistic ML-based matching

Train a model on labeled customer pairs to predict matches.

**Pros:** Highest theoretical accuracy.
**Cons:** Requires labeled training data we don't have. Black-box matching is impossible to explain to clients. Significantly more complex. Defer until we have data to train on.

---

## Decision

**Option C: Tiered fuzzy matching with confidence flags, override mechanism, and configurable thresholds.**

Implementation:

- **Tier 1 — Email match** (high confidence): SHA-256 of lowercased, trimmed email
- **Tier 2 — Phone match** (high confidence): E.164-normalized phone hash
- **Tier 3 — Fuzzy name+address** (medium confidence): Jaro-Winkler similarity on normalized name, exact postal-code-prefix match required, configurable threshold (default 0.92)

Every customer record carries `identity_resolution_method` and `match_confidence` columns so downstream consumers can see how each row was matched.

Clients can:
- Disable Tier 3 entirely via `vars.fuzzy_matching_enabled = false`
- Adjust similarity threshold via `vars.fuzzy_name_similarity_threshold`
- Require/relax postal match via `vars.require_postal_match`
- Override specific matches via `seeds/identity_overrides.csv`

A diagnostic view (`vw_identity_resolution_review`) surfaces all medium-confidence matches for review.

---

## Rationale

The user explicitly chose the fuzzy approach despite the false-positive risk. The risk is real but manageable when paired with three safeguards:

1. **Confidence flagging.** A medium-confidence match is not the same as a high-confidence match. Downstream reports can filter by `match_confidence = 'high'` for situations where strictness matters (compliance reporting, customer service lookups), and use all matches for situations where coverage matters (LTV analysis, marketing).

2. **Conservative defaults.** Jaro-Winkler 0.92 with required postal-prefix match is genuinely conservative. "John Smith" and "John Smyth" at the same postal code match (0.94 similarity). "John Smith" in San Francisco and "John Smith" in New York do not — different postal codes. Two genuinely different "John Smiths" in the same postal code are rare; when it happens, the override seed handles it.

3. **Override mechanism.** Clients are never locked into the algorithm's decisions. The `identity_overrides.csv` seed lets them split incorrectly merged customers or force merges that the algorithm missed. This converts a "trust the black box" problem into a "trust but verify, and adjust" problem.

The defaults can be tuned per client. Some D2C apparel brands will want aggressive matching (customers shop under multiple identities). Some B2B-leaning retailers will want strict matching (each company contact is a separate person, even if from the same address). The configuration handles both.

---

## Consequences

**Easier:**

- Customer counts in the warehouse reflect reality, not source-system artifacts
- LTV, retention, repeat-purchase, and cohort analyses produce trustworthy numbers
- Match coverage typically rises from 75–85% (email-only) to 95%+
- Clients have visibility and control over identity resolution

**Harder:**

- Implementation complexity is meaningfully higher than email-only matching
- Onboarding includes a review step for medium-confidence matches
- Documentation must clearly explain confidence flagging so analysts don't treat all matches as equivalent
- Sales conversations may need to address fuzzy matching directly with data-sophisticated buyers

**New decisions this creates:**

- What is the recommended review workflow for medium-confidence matches? (Operational playbook deferred to implementation handbook.)
- Should the diagnostic review view be in the OSS core or the pro tier? (Proposed: OSS core; review is fundamental hygiene, not premium functionality.)
- When labeled match data exists from real client deployments, should we revisit Option D (ML matching) for v2? (Defer; revisit in 18 months.)

---

## Related decisions

- ADR-002: Audit and Lineage Architecture (the audit columns help diagnose match issues)
- Section 4.3 of the canonical data model design (where the implementation is specified)
