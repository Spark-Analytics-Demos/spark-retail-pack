{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='order_id',
    on_schema_change='append_new_columns',
    cluster_by=['order_date', 'customer_sk']
) }}

-- fact_orders per §4.19. One row per Shopify order at header level.
-- Lookback: var(incremental_lookback_fact_orders_days, 14) days — covers refund updates.
-- customer_sk: SCD2-aware join to dim_customer at order_timestamp.
-- payment_method_sk: type-level match via Stripe charge (card brand when available).
-- refunded_amount: aggregated from stg_shopify__refunds VARIANT transactions.

with orders as (
    select * from {{ ref('stg_shopify__orders') }}
    {{ incremental_lookback('updated_at', 'fact_orders') }}
),

-- Compute FX rate once per order to avoid repeated correlated subquery per column
orders_fx as (
    select
        *,
        cast(
            {{ daily_fx_rate('original_currency_code', 'order_date') }}
            as numeric(18,8)
        )                                                               as fx_rate
    from orders
),

enriched as (
    select * from {{ ref('int_orders_enriched') }}
),

refund_totals as (
    select
        order_id,
        sum(
            coalesce((
                select sum(try_cast(t.value:amount as numeric(18,6)))
                from lateral flatten(input => refund_transactions, outer => true) t
                where lower(t.value:kind::varchar)   = 'refund'
                  and lower(t.value:status::varchar) = 'success'
            ), 0)
        )                                                               as refunded_amount_local
    from {{ ref('stg_shopify__refunds') }}
    group by order_id
),

-- Most-recent Stripe charge per Shopify order (for payment method resolution)
latest_charge as (
    select
        shopify_order_id                                                as order_id,
        lower(coalesce(payment_type, 'unknown'))                       as payment_type,
        lower(coalesce(card_brand,   ''))                              as card_brand,
        lower(coalesce(card_wallet,  ''))                              as card_wallet
    from {{ ref('stg_stripe__charges') }}
    where shopify_order_id is not null
    qualify row_number() over (
        partition by shopify_order_id
        order by charge_timestamp desc
    ) = 1
),

-- Resolve payment_method_sk via type-level match; QUALIFY ensures one row per order
charge_pm as (
    select
        lc.order_id,
        dpm.payment_method_sk
    from latest_charge lc
    left join {{ ref('dim_payment_method') }} dpm
        on dpm.payment_method_type = case
            when lc.payment_type = 'card' and lc.card_wallet != '' then 'digital_wallet'
            when lc.payment_type = 'card'                          then 'card'
            when lc.payment_type in ('klarna', 'afterpay_clearpay',
                                     'affirm', 'zip', 'laybuy')    then 'bnpl'
            when lc.payment_type in ('us_bank_account', 'ach_debit',
                                     'sepa_debit', 'bacs_debit',
                                     'au_becs_debit')              then 'bank_transfer'
            when lc.payment_type = 'link'                          then 'digital_wallet'
            else 'other'
        end
        -- For card: narrow by brand when available; accept any funding tier
        and (lc.payment_type != 'card'
             or lc.card_brand = ''
             or coalesce(dpm.card_brand, '') = lc.card_brand)
    qualify row_number() over (
        partition by lc.order_id
        order by coalesce(dpm.payment_method_id, 'zzz')   -- deterministic tie-break
    ) = 1
),

-- source_name → channel_mapping → channel_sk
channel_map as (
    select source_value, channel_id
    from {{ ref('channel_mapping') }}
    where source_system = 'shopify'
)

select
    {{ generate_dim_sk(['o.order_id']) }}                             as order_sk,
    o.order_id,
    o.order_number,

    -- Dimension FKs
    dc.customer_sk,
    dc.customer_id,
    dch.channel_sk,
    dg.geography_sk,
    cpm.payment_method_sk,

    -- Time
    o.order_date,
    o.order_timestamp,

    -- Status
    o.order_status,
    o.fulfillment_status,
    o.financial_status,

    -- Monetary amounts in reporting currency
    cast(o.gross_amount    * coalesce(o.fx_rate, 1.0) as numeric(18,4)) as gross_amount,
    cast(o.discount_amount * coalesce(o.fx_rate, 1.0) as numeric(18,4)) as discount_amount,
    cast(o.tax_amount      * coalesce(o.fx_rate, 1.0) as numeric(18,4)) as tax_amount,
    cast(o.shipping_amount * coalesce(o.fx_rate, 1.0) as numeric(18,4)) as shipping_amount,
    cast(o.tip_amount      * coalesce(o.fx_rate, 1.0) as numeric(18,4)) as tip_amount,
    cast(o.net_amount      * coalesce(o.fx_rate, 1.0) as numeric(18,4)) as net_amount,
    cast(coalesce(rt.refunded_amount_local, 0)
         * coalesce(o.fx_rate, 1.0) as numeric(18,4))                  as refunded_amount,
    cast((o.net_amount - coalesce(rt.refunded_amount_local, 0))
         * coalesce(o.fx_rate, 1.0) as numeric(18,4))                  as net_after_refunds,
    cast('{{ var("reporting_currency", "USD") }}' as varchar)           as currency_code,
    o.original_currency_code,
    cast(o.gross_amount as numeric(18,4))                               as original_gross_amount,
    coalesce(o.fx_rate, 1.0)                                            as fx_rate_to_reporting,

    -- Order metrics (from int_orders_enriched)
    coalesce(e.line_item_count, 0)                                      as line_item_count,
    coalesce(e.total_quantity,  0)                                      as total_quantity,
    coalesce(e.is_first_order,  false)                                  as is_first_order,
    coalesce(e.is_repeat_order, false)                                  as is_repeat_order,
    o.is_subscription_order,
    o.is_test_order,

    -- Tags and metadata
    o.discount_codes_raw                                                as discount_codes,
    o.primary_discount_code,
    split(coalesce(o.tags_raw, ''), ',')                                as tags,
    o.note,

    -- Attribution
    o.utm_source,
    o.utm_medium,
    o.utm_campaign,
    o.utm_content,
    o.utm_term,
    o.referrer_url,
    o.landing_page_url,
    o.cart_id,
    o.customer_email_hash_at_order,
    o.ip_address_hash,
    o.device_category,
    -- browser: user_agent available but not parsed to browser in v1
    cast(null as varchar)                                               as browser,

    o.order_timestamp                                                   as created_at,
    o.updated_at,
    current_timestamp()                                                 as loaded_at,

    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='o.order_id',
        business_columns=['o.order_id', 'o.updated_at'],
        extracted_at_column='o._extracted_at'
    ) }}

from orders_fx o
left join enriched e
    on e.order_id = o.order_id
left join refund_totals rt
    on rt.order_id = o.order_id
-- SCD2-correct customer: dim version active at order_timestamp
left join {{ ref('dim_customer') }} dc
    on dc.shopify_customer_id = o.shopify_customer_id
    and o.order_timestamp >= dc.valid_from
    and (o.order_timestamp < dc.valid_to or dc.valid_to is null)
    and o.shopify_customer_id is not null
-- Channel: exact source_name match, fall back to wildcard '*'
left join channel_map cm_exact
    on cm_exact.source_value = o.source_name
left join channel_map cm_wild
    on cm_wild.source_value = '*'
left join {{ ref('dim_channel') }} dch
    on dch.channel_id = coalesce(cm_exact.channel_id, cm_wild.channel_id)
-- Geography: shipping country (country-level rows; no sub-region)
left join {{ ref('dim_geography') }} dg
    on dg.country_code = o.shipping_country_code
    and dg.state_or_region_code is null
-- Payment method
left join charge_pm cpm
    on cpm.order_id = o.order_id
