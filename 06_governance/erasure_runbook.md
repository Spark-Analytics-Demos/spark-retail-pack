# Erasure Runbook — Spark Retail Pack

> **Purpose:** Step-by-step procedure for processing GDPR Article 17 right-to-erasure requests and CCPA opt-out requests against the Spark Retail Pack warehouse.
>
> **Authoritative source:** §8.10 of the design document; `customer_erasure` macro in `02_dbt_core/macros/customer_erasure.sql`.
>
> **Audience:** Compliance officers, data protection officers, and analytics engineers who execute erasure requests.
>
> **Last reviewed:** 2026-05-27 (v1 release)

---

## Overview

The erasure flow is implemented as code, not as a process. When a customer exercises their right to erasure, their personally identifiable information is cryptographically overwritten across all tables in the warehouse. The customer row itself is preserved for analytical integrity — order counts, revenue totals, and cohort metrics remain accurate; only identification is destroyed.

This pattern complies with GDPR Article 17 per EDPB guidance, which explicitly accepts pseudonymisation and aggregation as sufficient for analytical data retention beyond erasure.

---

## Erasure scopes

Two erasure scopes are available:

| Scope | Effect |
|---|---|
| `full_erasure` | All PII fields in `dim_customer`, `fact_orders`, `fact_web_sessions`, and `fact_email_engagement` are overwritten with a cryptographic redaction marker. Customer row persists with no identifying information. |
| `marketing_only` | Subscription flags set to `FALSE`; customer removed from active marketing audiences. PII fields are NOT erased — use for CCPA marketing opt-outs only, not for full erasure requests. |

**When in doubt, use `full_erasure`.** Use `marketing_only` only when the legal basis is explicitly a marketing opt-out, not a right-to-erasure request.

---

## Step-by-step procedure

### Step 1 — Receive and validate the request

Before proceeding, confirm:

- [ ] The requestor's identity has been verified per your compliance process (email ownership confirmation, ID check, etc.)
- [ ] No legal hold is in place for this customer (active litigation, fraud investigation, regulatory inquiry)
- [ ] The request falls within the regulatory scope (GDPR Art. 17, CCPA §1798.105, or equivalent)

Record the compliance ticket ID. This goes into the seed file in Step 2.

**Do not proceed if any hold condition applies.** Document the reason and notify the requestor within the regulatory response window (30 days for GDPR, 45 days for CCPA).

---

### Step 2 — Look up the customer_id

The erasure seed file uses internal `customer_id` (the Shopify customer ID), not email address.

Look up the `customer_id` using the contact lookup view (requires `RETAIL_PII_VIEWER` role):

```sql
SELECT customer_id, email, phone
FROM mart_customer.customer_contact_lookup
WHERE email = '<requestor_email>';
```

Record the `customer_id`. If multiple rows are returned (duplicate accounts), include all of them.

---

### Step 3 — Add to the erasure seed

Open `02_dbt_core/seeds/erasure_requests.csv`. Add one row per `customer_id` to be erased.

```csv
customer_id,request_date,ticket_id,scope,legal_basis
abc123,2026-05-27,GDPR-7421,full_erasure,gdpr_article_17
```

Field reference:

| Field | Format | Example |
|---|---|---|
| `customer_id` | Shopify customer ID string | `abc123` |
| `request_date` | ISO date of the erasure request | `2026-05-27` |
| `ticket_id` | Your compliance ticket reference | `GDPR-7421` |
| `scope` | `full_erasure` or `marketing_only` | `full_erasure` |
| `legal_basis` | Regulatory basis string | `gdpr_article_17` / `ccpa_1798_105` |

Commit the change to the seed file and push to your CI branch. Do **not** merge without a reviewer for `full_erasure` scope requests — a second pair of eyes reduces error risk.

---

### Step 4 — Run dbt to execute the erasure

The `customer_erasure` macro runs automatically during any `dbt build` or `dbt seed` + `dbt run` invocation when new rows exist in `erasure_requests.csv`.

For full erasure requests, trigger a production run:

```bash
dbt build --select +dim_customer+ --vars '{"erasure_mode": true}'
```

Or a full production run if other models are already queued:

```bash
dbt build
```

The macro will:

1. Identify all `customer_id` values in `erasure_requests.csv` that have not yet been processed (i.e., not in `metadata.erasure_log`)
2. For each `customer_id`:
   - Overwrite all PII fields in `dim_customer` with `SHA256(CONCAT('ERASED:', customer_id, ':redacted'))` — a deterministic marker that proves erasure without exposing original data
   - Apply the same redaction to `fact_orders.customer_email_hash_at_order`
   - Redact `fact_web_sessions` rows (set `user_pseudo_id` to redaction marker)
   - Redact `fact_email_engagement` rows (anonymise customer linkage)
   - Set `marketing_consent = FALSE`, `email_subscribed = FALSE`, `sms_subscribed = FALSE`
3. Write a row to `metadata.erasure_log` with `confirmation_hash` for audit

---

### Step 5 — Verify the erasure

After the dbt run completes, verify that the erasure executed:

```sql
-- Check erasure log
SELECT *
FROM metadata.erasure_log
WHERE ticket_id = '<your_ticket_id>';
```

Expected columns:

| Column | Expected value |
|---|---|
| `customer_id` | The erased customer ID |
| `ticket_id` | Your compliance ticket reference |
| `legal_basis` | As recorded in the seed |
| `scope` | `full_erasure` or `marketing_only` |
| `requested_at` | The `request_date` from the seed |
| `executed_at` | Timestamp of the dbt run |
| `executed_by` | The dbt invocation ID |
| `confirmation_hash` | Non-null cryptographic confirmation |

Then verify the PII fields are redacted in `dim_customer`:

```sql
SELECT customer_id, email, phone, first_name, last_name, city
FROM dim_customer
WHERE customer_id = '<erased_customer_id>';
```

All PII columns should return values beginning with `ERASED:` or a SHA-256 hash string. No plaintext name, email, or phone should appear.

---

### Step 6 — Notify source systems

**Critical:** The warehouse erasure covers only the analytical warehouse. The original data still exists in:

- **Shopify** — delete or anonymise via Shopify's "Request Data Erasure" webhook or admin API
- **Klaviyo** — suppress or delete the profile via Klaviyo's Profile Suppression API
- **Stripe** — Stripe auto-redacts customer data after account closure; follow Stripe's DPA procedure
- **Meta Ads / GA4** — if customer email is used for custom audiences, remove from those audiences

Your compliance process should handle source-system notifications. The pack does not automate this.

---

### Step 7 — Respond to the requestor

Once Step 5 confirms successful execution and Step 6 is underway, respond to the requestor within the regulatory window confirming:

- Erasure was executed in your analytics warehouse on [date]
- Source system notifications have been sent to [Shopify / Klaviyo / etc.]
- The `ticket_id` for their records

For GDPR requests: respond within 30 days of the original request (not within 30 days of execution). If you cannot complete the erasure within 30 days, notify the requestor with an explanation and extended timeline (up to 90 days total for complex cases).

---

## Erasure log retention

The `metadata.erasure_log` table is retained for 5 years even after the customer's data is erased. The log proves that the erasure happened — it must survive independent of the customer record.

The `confirmation_hash` column provides cryptographic non-repudiation: it is computed from the `customer_id`, `ticket_id`, `executed_at`, and the dbt invocation ID. Regulators can verify the hash to confirm the erasure record has not been tampered with.

---

## Edge cases

### Customer has placed no orders

The macro handles this gracefully. If no rows exist for the `customer_id` in fact tables, only `dim_customer` is redacted. The erasure log still records the event.

### Duplicate customer accounts (same person, multiple IDs)

Erase all `customer_id` values that resolve to the same individual. Each requires its own row in the seed file and will generate its own `erasure_log` entry.

### Customer requests erasure after having already been erased

If `customer_id` is already in `metadata.erasure_log` with `scope = full_erasure`, no further action is required. Reply to the requestor confirming the earlier erasure date from the log.

### Legal hold overrides

If a legal hold is placed on a customer after erasure has been queued but before the dbt run executes, **remove the row from the seed file before running**. Do not commit the hold reason to the erasure seed — maintain it in your compliance system. Contact your legal counsel.

---

## Summary: what IS and IS NOT erased

| Layer | What happens |
|---|---|
| `dim_customer` PII fields | **Overwritten** with redaction markers |
| `fact_orders` email hash | **Overwritten** with redaction markers |
| `fact_web_sessions` user linkage | **Anonymised** (customer_sk and customer_id redacted) |
| `fact_email_engagement` customer linkage | **Anonymised** |
| Order financial records | **Preserved** (no PII; needed for tax/audit trail) |
| `metadata.erasure_log` | **Written** (proof of erasure; retained 5 years) |
| Shopify source data | **Not touched by this pack** — handle separately |
| Klaviyo source data | **Not touched by this pack** — handle separately |
