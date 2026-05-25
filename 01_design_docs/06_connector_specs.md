# Section 6: Connector Specifications

> **Document status:** Draft v1
> **Audience:** Implementation engineers, analytics engineers integrating client data, future contributors adding new sources
> **Purpose:** Specify exactly how each of the 5 source systems maps into the canonical data model. For every source table consumed, this section documents the required fields, the canonical target columns, transformation logic, edge cases, and the YAML configuration clients use to customize mappings.

---

## 6.1 What this section defines

For each of the 5 source systems shipped with v1, this section specifies:

1. **Required source tables** — what the ingestion tool must load into bronze
2. **Required source fields** — the source contract that must be satisfied
3. **Optional fields** — fields the pack uses if present, but tolerates if absent
4. **Source-to-canonical mapping** — which source field populates which canonical column
5. **Transformation logic** — type casting, normalization, derivations
6. **Conflict resolution** — when multiple sources contribute to the same canonical column, which wins
7. **Edge cases and known issues** — quirks per source that staging models handle
8. **Configuration overrides** — YAML files clients can edit to change the default mapping

This is the contract between the ingestion layer and the canonical model. If a source meets its contract, the pack will work. If it doesn't, the pack fails fast at the staging layer with a clear error (per Section 4 Part 3, Section 4.38).

---

## 6.2 The mapping configuration pattern

Every source-to-canonical mapping in the pack is **configuration-driven**, not hardcoded. The mapping lives in YAML files in `seeds/source_mappings/`, read at build time by the `apply_source_mapping` macro (Section 4 Part 3, Section 4.47).

### Why configuration, not code

The reason a client can adopt the pack with minimal change is that **their column names rarely match ours exactly**. A client's Shopify export might have `customer_email` instead of `email`, or they might have renamed `total_price` to `final_amount` during a Fivetran customization. Forcing them to either rename their source data or fork the pack would kill adoption.

By making the mapping a YAML configuration:

- The same staging SQL code works for every client
- Clients edit a 30-line YAML file, not a 200-line SQL file
- Upgrades are non-breaking — the SQL changes, the YAML stays
- Mappings can be version-controlled and reviewed independently

### The standard mapping file structure

Every source has one mapping file per table. Example:

```yaml
# seeds/source_mappings/shopify__orders.yml
source: shopify
source_table: orders
target_model: stg_shopify__orders

# Required fields the source MUST provide
required_fields:
  - id
  - email
  - created_at
  - total_price
  - financial_status

# Optional fields the pack uses if present
optional_fields:
  - cart_token
  - tags
  - note
  - source_name

# Mapping of source columns to canonical staging columns
field_mappings:
  order_id: id
  customer_email: email
  order_timestamp: created_at
  gross_amount: subtotal_price
  net_amount: total_price
  tax_amount: total_tax
  shipping_amount: total_shipping_price_set.shop_money.amount
  discount_amount: total_discounts
  currency_code: currency
  financial_status: financial_status
  fulfillment_status: fulfillment_status

# Filters applied at staging
filters:
  exclude_test_orders: true
  exclude_archived: false
  min_created_at: '2020-01-01'  # ignore historical noise

# Transformation rules
transformations:
  customer_email:
    - lowercase
    - trim
  order_status:
    map_values:
      'paid': 'paid'
      'pending': 'pending'
      'authorized': 'pending'
      'partially_paid': 'pending'
      'refunded': 'refunded'
      'voided': 'cancelled'
      'partially_refunded': 'partial_refund'
```

Clients override any of these by editing the YAML file in their own deployment — without touching SQL.

---

## 6.3 Connector status overview

| Source | v1 status | Sync mode | Typical sync latency | Required for modules |
|---|---|---|---|---|
| **Shopify** | ✅ Production | Incremental + initial backfill | 1–4 hours | Sales, Customer 360, Inventory |
| **Stripe** | ✅ Production | Incremental + initial backfill | 1–4 hours | Sales, Customer 360 |
| **Google Analytics 4** | ✅ Production | Daily batch (GA4 limitation) | 24–48 hours | Customer 360 |
| **Meta Ads** | ✅ Production | Daily batch | 12–24 hours | Customer 360 |
| **Klaviyo** | ✅ Production | Incremental | 1–4 hours | Customer 360 |

All five connectors are recommended via **Fivetran** or **Airbyte**. The pack does not bundle the ingestion connector — clients use what they already have or pick one. Configuration documentation for both tools ships in `docs/ingestion/`.

---

## 6.4 Connector 1 — Shopify

### Overview

Shopify is the foundational source. It provides the data for Sales Analytics and Inventory Health entirely, and contributes the bulk of customer and product data to Customer 360. Most clients in the target market run on Shopify; the pack is opinionated about this.

**Source documentation:** [Shopify Admin API](https://shopify.dev/docs/api/admin)

### Required source tables

| Source table | Contains | Used by canonical models |
|---|---|---|
| `shopify.customers` | Customer profile records | `dim_customer` |
| `shopify.orders` | Order headers | `fact_orders` |
| `shopify.order_line_items` | Order line items (one row per line) | `fact_order_lines` |
| `shopify.refunds` | Refund events | `fact_refunds`, updates to `fact_orders.refunded_amount` |
| `shopify.products` | Product master | `dim_product` (parent) |
| `shopify.product_variants` | SKU variants | `dim_product` (variant-grain rows) |
| `shopify.inventory_levels` | Per-location stock | `fact_inventory_snapshot` |
| `shopify.inventory_items` | Inventory metadata (cost, barcode) | `dim_product` (cost, barcode) |
| `shopify.locations` | Warehouse/store locations | `dim_warehouse_location` |
| `shopify.transactions` | Payment transactions | `dim_payment_method`, `fact_orders.payment_method_sk` |

### Optional source tables

| Source table | Why optional | What's lost if absent |
|---|---|---|
| `shopify.fulfillments` | Not used in v1 (fulfillment module deferred) | Nothing in v1 |
| `shopify.discount_codes` | Used for discount-code analytics, but the `discount_codes` array on `orders` is sufficient | Discount-code-level analytics |
| `shopify.metafields` | Client-specific extended attributes | Custom-attribute analytics |

### Required source contract

The minimum fields each required table must provide:

**`shopify.customers`**
- `id` (not null)
- `email` (nullable, but expected on most records)
- `created_at` (not null)
- `updated_at` (not null)
- `phone` (nullable)
- `first_name`, `last_name` (nullable)
- `accepts_marketing` (boolean)
- `default_address` (object containing `country_code`, `city`, `province_code`, `zip`)

**`shopify.orders`**
- `id` (not null, unique)
- `customer.id` (nullable for guest orders)
- `email` (nullable but expected)
- `created_at` (not null)
- `updated_at` (not null)
- `subtotal_price` (not null)
- `total_price` (not null)
- `total_tax` (not null, may be 0)
- `total_discounts` (not null, may be 0)
- `currency` (not null, ISO 4217)
- `financial_status` (not null)
- `fulfillment_status` (nullable)
- `test` (boolean) — for filtering test orders

**`shopify.order_line_items`**
- `id` (not null, unique)
- `order_id` (not null)
- `variant_id` (nullable for custom items)
- `sku` (nullable, but expected)
- `quantity` (not null)
- `price` (not null)
- `total_discount` (not null, may be 0)

**`shopify.product_variants`**
- `id` (not null, unique)
- `product_id` (not null)
- `sku` (nullable but expected)
- `price` (not null)
- `inventory_quantity` (nullable)

If any required field is missing from the source, the staging model's `dbt source freshness` and source tests will fail before any downstream model runs, with a clear error.

### Source-to-canonical mappings

#### `shopify.customers` → `dim_customer`

| Canonical column | Source field | Transformation | Notes |
|---|---|---|---|
| `customer_id` | derived | SHA-256 hash of lowercased email | This is the canonical key, not Shopify's `id` |
| `email_hash` | `email` | SHA-256 of lowercased+trimmed | |
| `email` | `email` | lowercase+trim, then pii_mask | Hashed in gold unless PII viewer |
| `phone_hash` | `phone` | E.164 normalize, SHA-256 | |
| `phone` | `phone` | E.164 normalize, pii_mask | |
| `first_name`, `last_name` | `first_name`, `last_name` | trim, pii_mask | |
| `customer_status` | `state` | map: `enabled`→`active`, `disabled`→`blocked`, `declined`→`blocked`, `invited`→`active` | |
| `acquisition_channel` | `default_address.source_name` or `source_name` | mapped via channel seed | |
| `acquisition_source_system` | literal `'shopify'` | hardcoded in staging | |
| `acquisition_date` | `created_at` | cast to date | |
| `first_order_date` | derived | MIN(`orders.created_at`) for this customer | Computed in `int_customer_identity_resolution` |
| `last_seen_at` | derived | MAX of activity across all sources | Computed across sources |
| `country_code` | `default_address.country_code` | ISO 3166-1 alpha-2 | |
| `region` | `default_address.province_code` | | |
| `city` | `default_address.city` | pii_mask | |
| `postal_code_hash` | `default_address.zip` | normalize then SHA-256 | |
| `marketing_consent` | `accepts_marketing` | cast to boolean | |
| `email_subscribed` | `accepts_marketing` AND `marketing_opt_in_level IS NOT NULL` | derived | Klaviyo overrides if present |
| `sms_subscribed` | `accepts_sms_marketing` | cast to boolean | If field present in source |
| `customer_tags` | `tags` | split on comma, trim each | |
| `is_b2b_customer` | derived | TRUE if `tags` contains `b2b`/`wholesale`/`business` OR `default_address.company` is not null | |
| `created_at` | `created_at` | timestamp_tz | |
| `updated_at` | `updated_at` | timestamp_tz | |

#### `shopify.orders` → `fact_orders`

| Canonical column | Source field | Transformation | Notes |
|---|---|---|---|
| `order_id` | `id` | string | |
| `order_number` | `name` or `order_number` | string | Shopify formats as `#1042` |
| `customer_id` | `customer.id` then resolved via identity macro | | |
| `customer_email_hash_at_order` | `email` | SHA-256 of lowercased+trimmed | May differ from current customer email |
| `order_date` | `created_at` | cast to date in reporting timezone | |
| `order_timestamp` | `created_at` | timestamp_tz | |
| `order_status` | `financial_status` + `cancelled_at` | derived (see status mapping below) | |
| `fulfillment_status` | `fulfillment_status` | as-is | Nullable |
| `financial_status` | `financial_status` | as-is | Nullable |
| `gross_amount` | `subtotal_price` | numeric | Pre-discount, pre-tax, pre-shipping |
| `discount_amount` | `total_discounts` | numeric | |
| `tax_amount` | `total_tax` | numeric | |
| `shipping_amount` | `total_shipping_price_set.shop_money.amount` | numeric | Multi-currency aware |
| `tip_amount` | `total_tip_received` | numeric, default 0 | |
| `net_amount` | `total_price` | numeric | Final paid amount |
| `refunded_amount` | derived | SUM(`refunds.transactions.amount`) | Updated via merge on refund events |
| `currency_code` | derived | client's reporting currency | |
| `original_currency_code` | `currency` | ISO 4217 | |
| `original_gross_amount` | `subtotal_price` | before FX conversion | |
| `fx_rate_to_reporting` | derived | from `int_fx_rates_daily` keyed by `order_date` and `currency` | |
| `payment_method_sk` | derived from `transactions[0].gateway` and `payment_details` | mapped to `dim_payment_method` | |
| `channel_sk` | `source_name` | mapped via channel seed | E.g., `web` → `online_store` |
| `geography_sk` | `shipping_address.country_code` + `province_code` | FK lookup | |
| `line_item_count` | computed | COUNT of `line_items` | |
| `total_quantity` | computed | SUM of `line_items.quantity` | |
| `is_first_order` | derived | TRUE if `customer.id`'s earliest order_date = this order's date | Computed in `int_orders_enriched` |
| `is_repeat_order` | NOT `is_first_order` | derived | |
| `is_subscription_order` | derived | TRUE if `tags` contains `subscription` or `source_name = 'recharge'` | |
| `is_test_order` | `test` OR `tags` contains `test` | derived | Filtered out by default |
| `discount_codes` | `discount_codes[].code` | array | |
| `primary_discount_code` | `discount_codes[0].code` | first element | |
| `tags` | `tags` | split on comma | |
| `note` | `note` | as-is | |
| `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term` | `note_attributes` where `name LIKE 'utm_%'` | extracted | Shopify stores UTMs as note attributes by default |
| `referrer_url` | `landing_site_ref` or `note_attributes.referrer` | derived | |
| `landing_page_url` | `landing_site` | as-is | |
| `cart_id` | `cart_token` | as-is | |
| `ip_address_hash` | `browser_ip` | SHA-256 | |
| `device_category` | `client_details.browser_width` | derived (mobile<768, tablet<1024, desktop>=1024) | |
| `browser` | `client_details.user_agent` | parsed | |
| `created_at` | `created_at` | timestamp_tz | |
| `updated_at` | `updated_at` | timestamp_tz | |

##### Order status mapping

Shopify's `financial_status` + `cancelled_at` combine to determine canonical `order_status`:

| Shopify `financial_status` | Shopify `cancelled_at` | Canonical `order_status` |
|---|---|---|
| `pending`, `authorized` | NULL | `pending` |
| `paid`, `partially_paid` | NULL | `paid` |
| `refunded` | NULL | `refunded` |
| `partially_refunded` | NULL | `partial_refund` |
| `voided` | NULL | `cancelled` |
| any | NOT NULL | `cancelled` |

If `fulfillment_status = 'fulfilled'` AND `financial_status = 'paid'`, the canonical `order_status` is `fulfilled` (more granular than `paid`).

#### `shopify.order_line_items` → `fact_order_lines`

| Canonical column | Source field | Transformation | Notes |
|---|---|---|---|
| `line_item_id` | `id` | | |
| `order_id` | `order_id` | | |
| `sku` | `sku` | | |
| `product_title_at_sale` | `title` (line item title at time of sale) | | Preserves historical product name |
| `quantity` | `quantity` | numeric | |
| `unit_price` | `price` | numeric | |
| `unit_cost` | derived from `inventory_item.cost` at `order_date` | SCD2 lookup from `dim_product` | NULL if cost not tracked |
| `line_subtotal` | `quantity * price` | computed | |
| `line_discount` | `total_discount` + allocated order-level discount | derived (proportional allocation) | |
| `line_tax` | from `tax_lines` array | SUM of tax line amounts | |
| `line_net_amount` | `line_subtotal - line_discount` | computed | |
| `was_promotional` | `line_discount > 0` | computed | |
| `refunded_quantity` | derived from `refund_line_items` | updated via merge | |
| `refunded_amount` | derived from `refund_line_items` | | |
| `is_returned` | `refunded_quantity > 0` | computed | |
| `discount_codes` | order-level codes that applied to this line | array | |

#### `shopify.products` + `shopify.product_variants` → `dim_product`

The variant is the grain of `dim_product` (one row per SKU per version). Parent product attributes are denormalized onto each variant row.

| Canonical column | Source field | Notes |
|---|---|---|
| `sku` | `variants.sku` | Required; lines without SKU are excluded |
| `product_id` | `products.id` | |
| `variant_id` | `variants.id` | |
| `product_title` | `products.title` | |
| `variant_title` | `variants.title` | |
| `display_name` | `products.title + " - " + variants.title` | computed |
| `barcode` | `variants.barcode` | UPC/EAN |
| `product_handle` | `products.handle` | URL slug |
| `image_url` | `products.image.src` or `variants.image_id` resolved | |
| `product_type` | `products.product_type` | |
| `category` | derived | mapped via `seeds/product_category_mapping.csv` |
| `subcategory` | derived | |
| `vendor` | `products.vendor` | |
| `brand` | `products.vendor` (default) | overridable via tag |
| `tags` | `products.tags` | split on comma |
| `unit_price` | `variants.price` | |
| `compare_at_price` | `variants.compare_at_price` | |
| `unit_cost` | `inventory_items.cost` (joined via `variants.inventory_item_id`) | |
| `currency_code` | client's reporting currency | |
| `weight`, `weight_unit` | `variants.weight`, `variants.weight_unit` | |
| `is_taxable` | `variants.taxable` | |
| `requires_shipping` | `variants.requires_shipping` | |
| `is_active` | `products.status = 'active'` AND NOT `products.archived` | |
| `inventory_tracked` | `variants.inventory_management IS NOT NULL` | |
| `inventory_policy` | `variants.inventory_policy` | `deny` or `continue` |

#### `shopify.inventory_levels` → `fact_inventory_snapshot`

| Canonical column | Source field | Notes |
|---|---|---|
| `product_id` / `sku` | join via `inventory_item_id` → `variants.inventory_item_id` → `variants.sku` | |
| `location_id` | `location_id` | |
| `snapshot_date` | snapshot run date | Daily |
| `quantity_on_hand` | `available + committed` | Shopify reports `available` (net) and `committed` separately |
| `quantity_committed` | derived from open orders | Pack computes from `orders` where `fulfillment_status IS NULL` |
| `quantity_available` | `available` | |
| `quantity_incoming` | derived from `transfers` or `purchase_orders` if connector includes | NULL if not available |

### Conflict resolution rules

When the same customer appears in Shopify, Stripe, and Klaviyo, Shopify is the **primary source of truth** for:

- `email` (Shopify wins if all sources have an email for this customer)
- `phone`
- `country_code`
- `first_name`, `last_name`
- `created_at` (the canonical "customer creation date" is the earliest creation across all sources, but Shopify's record is the reference)

Klaviyo wins for `marketing_consent` and `email_subscribed` (Klaviyo is the system actually managing consent).

### Edge cases and known issues

**Test orders.** Shopify allows merchants to place test orders during setup. These have `test = true` or are tagged `test`. The pack filters them out by default (`exclude_test_orders: true`). Override per environment if testing the warehouse itself.

**Guest checkout.** Orders placed without an account have `customer.id = NULL` but typically have `email`. The pack uses email-based identity resolution to backfill these into `dim_customer` (per ADR-003). Guest orders without email are retained but flagged with `match_confidence = 'unmatched'`.

**Multi-currency orders.** Shopify Markets allows different storefronts in different currencies. The pack uses `currency` from the order and converts to reporting currency via daily FX rates. Discrepancies between `presentment_money` and `shop_money` are resolved in favor of `shop_money` (the merchant's actual receipt).

**Bundle products.** Shopify doesn't have native bundles; clients use apps that create multiple line items or single-line bundles. The pack treats whatever lines appear in `order_line_items` as the ground truth. Bundle-specific analytics are out of v1 scope.

**Order edits.** Shopify allows merchants to edit orders post-placement (adding/removing line items). Edits update `updated_at` on the order. The 14-day incremental lookback (Section 4 Part 3, Section 4.35) catches edits within that window. Edits older than 14 days require a manual refresh.

**Soft-delete vs. hard-delete.** Shopify soft-deletes customers (`state = 'declined'`) and archives products (`status = 'archived'`). It hard-deletes draft orders. The pack respects soft-deletes (keeps the row, flags it) and treats hard-deleted draft orders as never having existed.

**Cost data.** Shopify's `inventory_items.cost` is optional and many merchants leave it blank. The pack populates `unit_cost` where available and NULL otherwise; downstream KPIs that depend on cost (gross margin, inventory turnover) gracefully degrade to NULL rather than 0.

**Note attributes for UTMs.** Shopify doesn't natively capture UTMs on orders; convention is for the checkout to write them to `note_attributes`. If a merchant's storefront doesn't do this, UTMs on `fact_orders` will be NULL and attribution falls back to session-stitching via `fact_web_sessions`.

### Client configuration overrides

Three common overrides clients make to the Shopify mapping:

**1. Custom acquisition channel mapping.** A client running Shopify Plus with custom sales channels (e.g., a TikTok Shop integration) maps these to canonical channels:

```yaml
# seeds/source_mappings/shopify__channel_overrides.yml
channel_mappings:
  - source_name: tiktok-shop
    canonical_channel_id: marketplace_tiktok
    channel_category: marketplace
  - source_name: shop-app
    canonical_channel_id: shopify_shop_app
    channel_category: online_store
```

**2. Custom product category mapping.** Most clients customize the `product_type` → canonical category mapping:

```yaml
# seeds/product_category_mapping.csv (CSV seed, not YAML)
product_type,category,subcategory
"Men's Tees","Apparel","Tops"
"Coffee Beans","Food & Beverage","Coffee"
```

**3. Custom B2B detection rules.** Clients often have non-standard B2B markers:

```yaml
# seeds/source_mappings/shopify__b2b_rules.yml
b2b_detection:
  tag_patterns: ['wholesale', 'b2b', 'reseller', 'trade']
  company_field_required: true
  min_order_amount_for_b2b_flag: 500
```

---

## 6.5 Connector 2 — Stripe

### Overview

Stripe handles payment processing. It's a **secondary source of truth** for orders and customers (Shopify is primary), but **primary** for payment-method details, chargebacks, and any revenue that doesn't go through Shopify (e.g., direct API charges, subscriptions billed outside Shopify).

**Source documentation:** [Stripe API](https://stripe.com/docs/api)

### Required source tables

| Source table | Contains | Used by canonical models |
|---|---|---|
| `stripe.customers` | Stripe customer records | `dim_customer` (cross-reference) |
| `stripe.charges` | Successful payment events | `fact_orders` reconciliation, `dim_payment_method` |
| `stripe.refunds` | Refund events | `fact_refunds` |
| `stripe.disputes` | Chargebacks | `fact_refunds` (with `is_chargeback = TRUE`) |
| `stripe.payment_methods` | Stored payment methods | `dim_payment_method` |

### Optional source tables

| Source table | Why optional |
|---|---|
| `stripe.subscriptions` | Subscription module deferred to v2 |
| `stripe.invoices` | Used for non-Shopify revenue; optional if all revenue flows through Shopify |
| `stripe.payouts` | Useful for finance reconciliation but not analytical |
| `stripe.balance_transactions` | Fee analytics — not in v1 |

### Required source contract

**`stripe.charges`**
- `id` (not null, unique)
- `customer` (Stripe customer ID, may be null)
- `amount` (not null, integer cents)
- `currency` (not null, ISO 4217 lowercase)
- `created` (not null, Unix timestamp)
- `status` (not null: `succeeded`, `pending`, `failed`)
- `payment_method_details.type` (not null: `card`, `klarna`, etc.)
- `metadata.shopify_order_id` (nullable but expected when charge originates from Shopify)

**`stripe.customers`**
- `id` (not null, unique)
- `email` (nullable)
- `created` (not null)
- `phone` (nullable)

### Source-to-canonical mappings

#### `stripe.customers` → `dim_customer` (cross-reference)

Stripe customers are merged into `dim_customer` via email match. The intermediate model `int_customer_identity_resolution` performs the merge.

| Canonical column | Stripe source | Notes |
|---|---|---|
| `customer_id` | derived | hash of lowercased email |
| `source_systems` | adds `'stripe'` to array | tracks which sources have a record for this customer |
| All other fields | Shopify wins | Stripe contributes only when Shopify lacks data |

#### `stripe.charges` → reconciliation with `fact_orders`

Stripe charges are **not** loaded directly into `fact_orders`. Instead, they're used to:

1. **Verify** that `fact_orders.net_amount` matches `stripe.charges.amount` for orders originating from Shopify (linked via `metadata.shopify_order_id`).
2. **Populate** `fact_orders` for any charges **not** originating from Shopify (e.g., direct API charges, custom integrations).
3. **Populate** `dim_payment_method` with the actual payment method used.

Reconciliation discrepancies > 0.5% are flagged in the diagnostic view `vw_stripe_shopify_reconciliation`.

| `fact_orders` column | Stripe source | Notes |
|---|---|---|
| `payment_method_sk` | `payment_method_details.type` + `payment_method_details.card.brand` | mapped to `dim_payment_method` |
| `net_amount` (verification) | `amount / 100` (convert cents to dollars) | should match Shopify within tolerance |

#### `stripe.refunds` and `stripe.disputes` → `fact_refunds`

| `fact_refunds` column | Stripe source | Notes |
|---|---|---|
| `refund_id` | `id` | for `refunds`; for `disputes`, use `disputes.id` with prefix `dispute_` |
| `order_sk` | derived | via `charges.id` → `metadata.shopify_order_id` → `fact_orders.order_id` |
| `refund_date` | `created` | timestamp converted to date |
| `refund_type` | `'full_refund'` if `amount = charge.amount`, else `'partial_refund'`; `'chargeback'` if from disputes table | |
| `refund_reason` | `reason` | E.g., `requested_by_customer`, `fraudulent`, `duplicate` |
| `refund_amount` | `amount / 100` | |
| `processor` | literal `'stripe'` | |
| `is_chargeback` | TRUE if from disputes table, else FALSE | |

### Conflict resolution rules

When Stripe and Shopify both report a charge:

- **Net amount** — Shopify wins if values are within 0.5% tolerance. If outside tolerance, the discrepancy is logged and Stripe's value is used (it represents what actually settled).
- **Payment method** — Stripe wins (more granular data — knows card brand, BNPL provider, etc.).
- **Customer** — Shopify wins (primary source).

### Edge cases and known issues

**Stripe stores amounts in cents.** All amount conversions multiply by 0.01 in staging. Currency codes are lowercase in Stripe but uppercase elsewhere — staging normalizes to uppercase.

**Test mode vs. live mode.** Stripe has explicit test and live environments. Test charges have `livemode = false`. The pack filters to `livemode = true` by default.

**Disputes are not refunds.** A chargeback initiated by the cardholder is in `stripe.disputes`, not `stripe.refunds`. The pack merges both into `fact_refunds` with `is_chargeback` distinguishing them.

**Multi-currency charges.** Stripe converts to the merchant's settlement currency automatically; `amount` is always in `currency`. The pack uses this currency, not Stripe's account currency.

**Direct API charges (non-Shopify revenue).** Some clients use Stripe for revenue that doesn't pass through Shopify (subscriptions, B2B invoicing, custom apps). These charges have no `metadata.shopify_order_id`. The pack creates a synthetic `fact_orders` row for each, with `_source_system = 'stripe'` (per audit columns, Section 4.31). These show up as a `stripe_direct` channel in `dim_channel`.

**Refund partial fulfillment.** A refund may apply to only some line items. Stripe doesn't break out line-level refund data; that comes from Shopify's `refunds.refund_line_items`. The pack treats Shopify as source of truth for line-level refund detail, Stripe as source of truth for the payment-side refund record.

### Client configuration overrides

```yaml
# seeds/source_mappings/stripe__overrides.yml
reconciliation:
  tolerance_pct: 0.5  # discrepancy threshold for flag
  excluded_metadata_fields: ['internal_test', 'staging']
  
direct_charge_handling:
  create_synthetic_orders: true
  synthetic_channel_id: stripe_direct
```

---

## 6.6 Connector 3 — Google Analytics 4 (GA4)

### Overview

GA4 provides web session data for Customer 360 — visitor behavior, acquisition source, conversion attribution. GA4's data model is event-based, which the pack aggregates to sessions in the silver layer.

**Source documentation:** [GA4 BigQuery Export Schema](https://support.google.com/analytics/answer/7029846)

### Critical note: GA4 → Snowflake path

GA4 doesn't have a direct Snowflake connector. Two paths are supported:

1. **Recommended:** GA4 → BigQuery (free native export) → Fivetran/Airbyte BigQuery connector → Snowflake. ~24 hour latency.
2. **Alternative:** Third-party connectors that use GA4 Reporting API (Fivetran's connector, Stitch's, Airbyte's). Faster but rate-limited and aggregated.

The pack supports both. Path 1 gives event-level data (richer); Path 2 gives session-level data (faster, less detailed).

### Required source tables

The exact tables depend on the ingestion path. Documented for Path 1 (BigQuery export):

| Source table | Contains | Used by |
|---|---|---|
| `ga4.events_<date>` | Event-level data (page views, purchases, etc.) | Aggregated to `fact_web_sessions` |
| `ga4.users` | User-level metadata | Cross-reference with `dim_customer` |

For Path 2 (API-based):

| Source table | Contains |
|---|---|
| `ga4.sessions` | Pre-aggregated session data |
| `ga4.traffic_sources` | Acquisition source by session |
| `ga4.events` | Event counts by session |

### Required source fields

**Events approach (BigQuery export):**
- `event_date` (not null)
- `event_timestamp` (not null)
- `event_name` (not null)
- `user_pseudo_id` (not null — GA4's anonymous client ID)
- `user_id` (nullable — if site sets logged-in user ID)
- `device.category` (not null)
- `traffic_source.source`, `traffic_source.medium`, `traffic_source.name` (nullable)
- `ga_session_id` (not null — derived from event params)
- `page_location` (nullable, present on page_view events)

**Session aggregation (per session):**
- `purchase` event presence indicates a conversion
- `purchase.transaction_id` ties session to a specific order
- `purchase.value`, `purchase.currency` for revenue attribution

### Source-to-canonical mappings

#### GA4 events → `fact_web_sessions`

The session aggregation logic in `int_ga4_session_aggregation` produces one row per session:

| Canonical column | GA4 source | Transformation |
|---|---|---|
| `session_id` | `ga_session_id` + `user_pseudo_id` | composite key |
| `user_pseudo_id` | `user_pseudo_id` | |
| `customer_sk` | join `user_id` → `dim_customer` (when user_id present) | NULL for anonymous sessions |
| `channel_sk` | mapped from `traffic_source.source` + `traffic_source.medium` | via dim_channel seed |
| `geography_sk` | `geo.country` + `geo.region` | |
| `session_date` | first event's `event_date` | |
| `session_start_timestamp` | first event's `event_timestamp` | |
| `session_duration_seconds` | last event - first event | |
| `page_views` | COUNT(events WHERE event_name = 'page_view') | |
| `events_count` | COUNT(events) | |
| `device_category` | first event's `device.category` | |
| `device_brand` | first event's `device.mobile_brand_name` | |
| `device_os` | first event's `device.operating_system` | |
| `browser` | first event's `device.web_info.browser` | |
| `traffic_source` | `traffic_source.source` | |
| `traffic_medium` | `traffic_source.medium` | |
| `traffic_campaign` | `traffic_source.name` | |
| `traffic_content` | extracted from event params where key = `content` | |
| `traffic_term` | extracted from event params where key = `term` | |
| `landing_page` | first page_view event's `page_location` | |
| `exit_page` | last page_view event's `page_location` | |
| `has_purchase_event` | EXISTS event_name = 'purchase' | |
| `transaction_revenue` | purchase event's `value` | converted to reporting currency |
| `is_new_user` | first session for this `user_pseudo_id` | |

### Conflict resolution rules

GA4 is the **sole source** for session and web behavior data. No conflict resolution needed — there's no alternative source for the same data.

For customer attribution: GA4's `user_id` matches `dim_customer.customer_id` when the site implements GA4's User-ID feature (most don't reliably). For sites without User-ID, `user_pseudo_id` stays anonymous in `fact_web_sessions` — back-filled via purchase events that include logged-in user info.

### Edge cases and known issues

**GA4 latency.** GA4's BigQuery export updates daily, typically with a 24–48 hour delay. The pack's source freshness threshold for GA4 is set generously (12 hours warn, 48 hours error) to accommodate this. Real-time GA4 data is not supported.

**GA4 sampling.** GA4 samples data above certain query volumes. The BigQuery export is **not** sampled (full event-level data); the Reporting API **is** sampled. This is the main reason Path 1 (BigQuery) is recommended.

**user_pseudo_id is device-scoped.** The same person browsing on phone and desktop appears as two users. The pack documents this limitation — proper cross-device stitching requires User-ID or proprietary device-graph (deferred to v2).

**Cookieless / consent-mode traffic.** When users refuse cookies, GA4 models partial data. These sessions appear with limited attribution. The pack treats them as "(direct)" traffic by default; consent-aware attribution is a v2 concern.

**Apple's iOS privacy.** ITP and Apple Mail Privacy affect GA4 measurements (especially open rates). Documented in dashboards; not corrected in metrics.

**Bot filtering.** GA4 filters known bots, but some leak through. The pack adds an additional filter: sessions with `events_count = 1` AND `session_duration_seconds = 0` are flagged but not removed by default.

**Cross-domain sessions.** If a site spans multiple domains, GA4 may report duplicate sessions. The pack uses `ga_session_id + user_pseudo_id` as the session key, which dedupes most cases.

### Client configuration overrides

```yaml
# seeds/source_mappings/ga4__overrides.yml
ingestion_path: bigquery_export  # or 'api'
reporting_timezone: 'America/New_York'  # GA4 reports in property timezone

bot_filtering:
  exclude_zero_duration_single_event: false  # set true to exclude likely bots

attribution:
  channel_grouping_overrides:
    - source: "newsletter"
      medium: "email"
      canonical_channel: "email_marketing"
```

---

## 6.7 Connector 4 — Meta Ads

### Overview

Meta Ads (Facebook + Instagram) provides paid marketing spend data for Customer 360 — campaign-level spend, impressions, clicks, and platform-reported conversions. The pack uses Meta data for spend (authoritative) and platform-reported conversions (for reference, not attribution).

**Source documentation:** [Meta Marketing API](https://developers.facebook.com/docs/marketing-api/)

### Required source tables

| Source table | Contains | Used by |
|---|---|---|
| `meta_ads.campaigns` | Campaign master | `dim_marketing_campaign` |
| `meta_ads.ad_sets` | Ad set master | `dim_marketing_campaign` (rolled up) |
| `meta_ads.ads` | Individual ad metadata | `dim_marketing_campaign` (denormalized) |
| `meta_ads.daily_insights` | Daily spend and performance per ad/ad_set/campaign | `fact_marketing_spend` |

### Required source fields

**`meta_ads.campaigns`**
- `id` (not null, unique)
- `name` (not null)
- `objective` (not null)
- `status` (not null)
- `created_time` (not null)
- `start_time` (nullable)
- `stop_time` (nullable)
- `daily_budget` or `lifetime_budget` (one or the other, not null)
- `account_id` (not null)

**`meta_ads.daily_insights`**
- `date_start` (not null)
- `campaign_id` (not null)
- `ad_set_id`, `ad_id` (nullable depending on aggregation level)
- `spend` (not null, decimal in account currency)
- `impressions` (not null)
- `clicks` (not null)
- `actions` (array of action types and counts — includes purchases)

### Source-to-canonical mappings

#### `meta_ads.campaigns` → `dim_marketing_campaign`

| Canonical column | Meta source | Notes |
|---|---|---|
| `campaign_id` | `'meta_' + id` | prefix for cross-platform uniqueness |
| `platform` | literal `'meta'` | |
| `campaign_name` | `name` | |
| `campaign_objective` | `objective` | mapped to canonical values |
| `campaign_status` | `status` | mapped |
| `buying_type` | `buying_type` | |
| `start_date` | `start_time` cast to date | |
| `end_date` | `stop_time` cast to date | nullable |
| `daily_budget` | `daily_budget / 100` | Meta stores in cents |
| `lifetime_budget` | `lifetime_budget / 100` | |
| `utm_source` | derived | from `ads.tracking_specs` or convention `'facebook'`/`'instagram'` |
| `utm_medium` | derived | typically `paid_social` |
| `utm_campaign` | derived | from URL params in `ads.creative.link_url` or campaign name pattern |
| `target_audience` | from `ad_sets.targeting.custom_audiences` | extracted |
| `channel_sk` | mapped to `paid_social_meta` channel | |
| `created_at` | `created_time` | |

#### `meta_ads.daily_insights` → `fact_marketing_spend`

| Canonical column | Meta source | Notes |
|---|---|---|
| `campaign_id` | `'meta_' + campaign_id` | prefix |
| `spend_date` | `date_start` | |
| `spend_amount` | `spend` | already in decimal; converted to reporting currency |
| `original_currency_code` | from `ad_account.currency` | |
| `original_spend_amount` | `spend` | pre-conversion |
| `impressions` | `impressions` | |
| `clicks` | `clicks` | |
| `conversions_reported_by_platform` | from `actions` array WHERE `action_type = 'purchase'` | |
| `conversion_value_reported_by_platform` | from `action_values` array WHERE `action_type = 'purchase'` | |

### Conflict resolution rules

No conflicts — Meta is the sole source for its own data.

For attribution (which channel drove which order), the **warehouse uses UTM matching**, not Meta's reported conversions. The platform-reported conversions are kept in `fact_marketing_spend.conversions_reported_by_platform` for side-by-side comparison.

### Edge cases and known issues

**Platform-reported conversions are inflated.** Meta typically reports 2–4× more conversions than warehouse-attributed analysis shows, due to:
- 7-day click + 1-day view attribution windows (broad)
- Modeled conversions (Apple's iOS 14+ privacy framework)
- Cross-device attribution included
- Double-counting across campaigns

The pack documents this delta and reports both numbers separately. The "true" ROAS uses warehouse data.

**Spend currency.** Meta spend is in the ad account's currency, which may differ from the merchant's reporting currency. The pack converts using daily FX rates.

**Account-level vs. ad-level granularity.** Insights can be pulled at campaign, ad set, or ad level. The pack pulls at the ad level (most granular) and rolls up. Clients with very high ad counts (>10K active ads) may need ad-set-level granularity for performance — configurable.

**Campaign hierarchy.** Meta has Campaign → Ad Set → Ad. The pack uses Campaign as the dimension grain. Ad Set and Ad attributes are denormalized into `dim_marketing_campaign` only where they're stable; volatile attributes (creative URL, etc.) live in mart tables.

**Naming convention dependencies.** Many clients encode UTM info in campaign names (e.g., `2026-Q2_BlackFriday_Conversion_US`). The pack's UTM extraction macro can parse common patterns, but custom naming requires client-specific config.

**Disabled accounts.** When a Meta ad account is disabled or banned, historical data remains accessible via the API for a period. The pack flags such accounts via `is_active` on the account dimension (not exposed in v1) and surfaces in observability.

**Attribution windows in Meta vary.** Meta defaults to 7-day click attribution. Some accounts use 1-day view + 7-day click. The pack imports Meta's defaults; clients comparing dashboards should be aware which window applies.

### Client configuration overrides

```yaml
# seeds/source_mappings/meta_ads__overrides.yml
granularity: ad  # 'campaign', 'ad_set', or 'ad'

campaign_name_parsing:
  # Extract utm_campaign from campaign names like "Q2_BlackFriday_Conversion"
  enabled: true
  pattern: '(?P<year>\d{4})?[-_]?(?P<quarter>Q\d)?[-_]?(?P<theme>\w+)[-_]?(?P<objective>\w+)'

reconciliation:
  platform_vs_warehouse_conversion_ratio_warn_threshold: 3.0
  platform_vs_warehouse_conversion_ratio_error_threshold: 10.0
```

---

## 6.8 Connector 5 — Klaviyo

### Overview

Klaviyo provides email and SMS marketing engagement data for Customer 360. The pack uses Klaviyo for: email campaign metadata, individual customer engagement events (opens, clicks, etc.), and consent / subscription status.

**Source documentation:** [Klaviyo API](https://developers.klaviyo.com/en/reference/api_overview)

### Required source tables

| Source table | Contains | Used by |
|---|---|---|
| `klaviyo.profiles` | Customer profile records | `dim_customer` (cross-reference) |
| `klaviyo.events` | Engagement events (opens, clicks, etc.) | `fact_email_engagement` |
| `klaviyo.campaigns` | Email campaign master | `dim_email_campaign` |
| `klaviyo.flows` | Automated email flow master | `dim_email_campaign` (with `campaign_type = 'flow'`) |

### Optional source tables

| Source table | Why optional |
|---|---|
| `klaviyo.lists` | Useful for segment analytics, not in v1 |
| `klaviyo.segments` | Dynamic segments — used for segment movement (v2) |

### Required source fields

**`klaviyo.profiles`**
- `id` (not null, unique)
- `email` (nullable, but expected)
- `phone_number` (nullable)
- `created` (not null)
- `consent_status` or equivalent (nullable)

**`klaviyo.events`**
- `id` (not null, unique)
- `event_name` (not null — `Opened Email`, `Clicked Email`, etc.)
- `profile_id` (not null — links to `profiles.id`)
- `datetime` (not null)
- `event_properties` (object — campaign details, link clicked, etc.)
- `campaign_id` or `flow_id` (nullable — one of these for marketing events)

**`klaviyo.campaigns`**
- `id` (not null, unique)
- `name` (not null)
- `subject` (not null)
- `send_time` (nullable — null for unsent / scheduled)
- `status` (not null)

### Source-to-canonical mappings

#### `klaviyo.profiles` → `dim_customer` (cross-reference)

| Canonical column | Klaviyo source | Notes |
|---|---|---|
| `customer_id` | derived | hash of email — same as Shopify/Stripe |
| `email_subscribed` | `email_consent.consent_status = 'subscribed'` | Klaviyo wins over Shopify here |
| `sms_subscribed` | `sms_consent.consent_status = 'subscribed'` | |
| `marketing_consent` | derived | TRUE if `email_subscribed` OR `sms_subscribed` |
| `source_systems` | adds `'klaviyo'` to array | |

For unmatched profiles (email not in Shopify or Stripe), the pack creates `dim_customer` rows with `acquisition_source_system = 'klaviyo'` and `match_confidence = 'medium'` (per ADR-003).

#### `klaviyo.events` → `fact_email_engagement`

The mapping converts Klaviyo's freeform event names to canonical event types:

| Klaviyo `event_name` | Canonical `event_type` |
|---|---|
| `Received Email` | `delivered` |
| `Opened Email` | `opened` |
| `Clicked Email` | `clicked` |
| `Bounced Email` | `bounced` |
| `Unsubscribed` | `unsubscribed` |
| `Marked Email as Spam` | `marked_spam` |
| `Placed Order` (tied to email) | `converted` |

| Canonical column | Klaviyo source |
|---|---|
| `event_id` | `id` |
| `customer_sk` | join `profile_id` → `dim_customer` via email |
| `email_campaign_sk` | join `campaign_id` or `flow_id` → `dim_email_campaign` |
| `event_type` | mapped from `event_name` |
| `event_date` | `datetime` cast to date |
| `event_timestamp` | `datetime` |
| `email_subject` | `event_properties.subject` (snapshot at send) |
| `link_url` | `event_properties.URL` (for click events) |
| `bounce_type` | `event_properties.bounce_type` (for bounce events) |
| `bounce_reason` | `event_properties.reason` |
| `device_type` | `event_properties.user_agent` parsed |

#### `klaviyo.campaigns` → `dim_email_campaign`

| Canonical column | Klaviyo source | Notes |
|---|---|---|
| `email_campaign_id` | `id` | |
| `campaign_name` | `name` | |
| `campaign_type` | literal `'campaign'` for campaigns, `'flow'` for flows | from union of campaigns and flows |
| `subject_line` | `subject` | |
| `send_date` | `send_time` cast to date | NULL for flows / unsent |
| `target_segment` | `audience.name` | for campaigns; flows use trigger name |
| `audience_size` | `recipient_count` | |
| `is_active` | `status = 'sent'` for campaigns, `status = 'live'` for flows | |

### Conflict resolution rules

Klaviyo is the **primary source** for:
- Email subscription status (`email_subscribed`)
- SMS subscription status (`sms_subscribed`)
- Marketing consent (`marketing_consent`)

Shopify is primary for everything else on `dim_customer`. The merge in `int_customer_identity_resolution` is documented in Section 4 Part 1, Section 4.3.

### Edge cases and known issues

**Klaviyo event volume.** A busy Klaviyo account generates millions of events per month. Initial sync can take 6–12 hours for active accounts. The pack's source freshness is set to 6 hours warn / 24 hours error.

**Profile creation without consent.** Klaviyo creates profiles for unsubscribed contacts (e.g., people who download a lead magnet but don't consent to email). These show up in `klaviyo.profiles` with `consent_status = 'never_subscribed'`. The pack still includes them in `dim_customer` (they may have made a purchase later) but marks `marketing_consent = FALSE`.

**Flows vs. campaigns.** Flows are automated and reusable (welcome series, abandoned cart); campaigns are one-time sends. Both produce events. The pack unifies them into `dim_email_campaign` with `campaign_type` distinguishing.

**Email opens are unreliable.** Apple Mail Privacy Protection (introduced 2021) pre-fetches all images, inflating "open" events. The pack treats opens as a directional signal, not an exact count. Clients can configure `vars.exclude_mpp_opens = true` to filter Apple Mail opens specifically (requires User-Agent parsing).

**Profile merges.** Klaviyo merges duplicate profiles over time. When a merge happens, events from the old profile are reassociated with the new. The pack's incremental load handles this via the 30-day lookback on `fact_email_engagement`.

**Custom events.** Clients can create custom Klaviyo events (e.g., `Viewed Product`). The pack ignores custom events by default in v1; clients can extend by adding event name mappings in the override config.

**Phone vs. email.** Klaviyo profiles can be identified by email or phone. For email-only marketing programs, missing phone is expected. For SMS programs, missing email may break customer resolution — the pack handles via phone-based identity match (Tier 2 in ADR-003).

### Client configuration overrides

```yaml
# seeds/source_mappings/klaviyo__overrides.yml
event_name_mappings:
  # Add custom Klaviyo events to canonical event types
  - klaviyo_name: 'Viewed Product'
    canonical_event_type: 'product_view'
  - klaviyo_name: 'Added to Cart'
    canonical_event_type: 'cart_add'

mpp_filtering:
  enabled: false  # set true to filter Apple Mail Privacy opens
  
consent_overrides:
  # If Klaviyo consent should NOT override Shopify (some clients prefer Shopify)
  let_shopify_win: false
```

---

## 6.9 Adding new connectors

Future connector additions (Google Ads, TikTok Ads, Zendesk, etc.) follow a standard pattern. Documented here for v2 contributors.

### The connector addition checklist

1. **Document the connector spec** in this section format: source tables, required fields, mapping, edge cases, overrides.
2. **Create staging models** under `models/staging/<source>/` following the naming convention `stg_<source>__<table>.sql`.
3. **Define source freshness** in the source YAML.
4. **Add the source mapping seed files** under `seeds/source_mappings/<source>__<table>.yml`.
5. **Update `dim_customer` identity resolution** if the source contributes customer data.
6. **Add tests** following Section 4 Part 3, Section 4.37.
7. **Document edge cases** in a `docs/connectors/<source>.md` operational file.
8. **Add the connector to the matrix** in Section 6.3 and Section 6.10.
9. **Update the Module Breakdown** (Section 3) if the connector enables a new module or extends an existing one.

### Connectors prioritized for v2

| Connector | Why | Module |
|---|---|---|
| Google Ads | Most clients run Google + Meta; second largest paid channel | Customer 360 |
| TikTok Ads | Growing in D2C apparel and beauty | Customer 360 |
| Amazon Seller Central | Marketplace clients | Sales Analytics extension |
| Zendesk / Gorgias | Customer service KPIs | New module |
| Recharge | Subscription analytics | New module |
| Smile.io / LoyaltyLion | Loyalty analytics | New module |
| QuickBooks / NetSuite | Finance reconciliation | Sales Analytics extension |

---

## 6.10 Connector-to-canonical model coverage matrix

A consolidated view of which canonical models each connector populates.

| Canonical model | Shopify | Stripe | GA4 | Meta Ads | Klaviyo |
|---|---|---|---|---|---|
| `dim_customer` | **Primary** | Cross-ref | Cross-ref via user_id | – | Cross-ref + consent |
| `dim_product` | **Primary** | – | – | – | – |
| `dim_date` | (generated, not from source) |
| `dim_channel` | Contributes (sales channels) | – | Contributes (traffic sources) | Contributes (paid) | Contributes (email) |
| `dim_geography` | Contributes (addresses) | – | Contributes (visitor geo) | – | – |
| `dim_payment_method` | Contributes | **Primary** | – | – | – |
| `dim_warehouse_location` | **Primary** | – | – | – | – |
| `dim_marketing_campaign` | – | – | – | **Primary** | – |
| `dim_email_campaign` | – | – | – | – | **Primary** |
| `fact_orders` | **Primary** | Reconciliation + direct charges | – | – | – |
| `fact_order_lines` | **Primary** | – | – | – | – |
| `fact_refunds` | Contributes | **Primary** | – | – | – |
| `fact_marketing_spend` | – | – | – | **Primary** | – |
| `fact_web_sessions` | – | – | **Primary** | – | – |
| `fact_email_engagement` | – | – | – | – | **Primary** |
| `fact_customer_state_daily` | (generated from facts above) |
| `fact_inventory_snapshot` | **Primary** | – | – | – | – |
| `fact_inventory_movements` | **Primary** | – | – | – | – |

---

## 6.11 Connector-to-KPI dependency matrix

A consolidated view of which connectors a KPI depends on. Useful for clients adopting only some modules and wanting to know which connectors they can skip.

| KPI module | Required connectors |
|---|---|
| **Sales Analytics** (KPIs 1–9) | Shopify (required) + Stripe (required for payment reconciliation and accurate payment-method analytics) |
| **Customer 360** (KPIs 10–19) | Shopify (required) + Stripe (required) + GA4 (required for sessions) + Meta Ads (required for CAC/ROAS) + Klaviyo (required for email engagement) |
| **Inventory Health** (KPIs 20–25) | Shopify (required) |

A client adopting only Sales Analytics needs Shopify + Stripe. A client adopting Inventory Health only needs Shopify. Customer 360 requires all five connectors.

**Strictly minimum deployment:** Sales Analytics can technically function on Shopify alone (with reduced precision on payment-method analytics and no Stripe reconciliation), but this is not a recommended production deployment. The pack treats Stripe as required for Sales Analytics in all client implementations.

---

## 6.12 Onboarding sequence for new clients

A typical client onboarding follows this connector sequence:

| Phase | Duration | Connectors | What's enabled |
|---|---|---|---|
| **Phase 0: Setup** | Week 0 | (none) | Snowflake account, dbt project, ingestion tool selection |
| **Phase 1: Foundation** | Week 1 | Shopify, Stripe | Sales Analytics, Inventory Health, basic `dim_customer` |
| **Phase 2: Marketing** | Week 2 | + Meta Ads | Spend tracking, basic CAC (no attribution yet) |
| **Phase 3: Attribution** | Week 3 | + GA4 | Session data, UTM-based attribution, true ROAS |
| **Phase 4: Retention** | Week 4 | + Klaviyo | Email engagement, retention analytics, full Customer 360 |

This sequence allows incremental value delivery. A client gets working dashboards in Week 1 (Sales) rather than waiting for full deployment. Most enterprise clients run all five connectors concurrently and complete onboarding in 2–3 weeks instead of 4.

---

## 6.13 Summary

Five connectors define the v1 source contract for the Spark Retail Pack:

- **Shopify** — primary source for orders, products, inventory; cross-reference for customers
- **Stripe** — primary for payment methods and chargebacks; reconciliation for orders
- **GA4** — sole source for web behavior and acquisition attribution
- **Meta Ads** — primary for paid marketing spend (v2 adds Google, TikTok)
- **Klaviyo** — primary for email engagement and marketing consent

Every connector's source-to-canonical mapping is configuration-driven, so clients can customize without forking. Every connector has documented edge cases — the result of real-world implementation experience encoded into the pack.

The next section (Section 7) defines how the canonical model and KPIs from Sections 4 and 5 are exposed to consumers via the **semantic layer** — metric definitions in MetricFlow YAML, business glossary, and entity ontology.

---

**Previous:** [Section 5: KPI Catalog](./05_kpi_catalog.md)
**Next:** [Section 7: Semantic Layer](./07_semantic_layer.md)
