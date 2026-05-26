{{ config(
    materialized='incremental',
    incremental_strategy='append',
    unique_key='refund_id',
    on_schema_change='append_new_columns',
    cluster_by=['refund_date', 'order_sk']
) }}

-- fact_refunds per §4.21. One row per refund event.
-- Source: stg_shopify__refunds (primary); stg_stripe__refunds (processor metadata).
-- refund_amount: sum of refund_transactions VARIANT where kind='refund' and status='success'.
-- refund_category: regex-free keyword CASE on refund_note (full regex mapping is Pro v2).
-- is_chargeback: TRUE when Stripe charge has a dispute (requires stg_stripe__disputes).
-- Lookback: 30 days — chargebacks can arrive weeks after the original transaction.

with refunds as (
    select * from {{ ref('stg_shopify__refunds') }}
    {{ incremental_lookback('refund_timestamp', 'fact_refunds') }}
),

-- Parse refund_transactions VARIANT to extract refund amounts
refund_amounts as (
    select
        r.refund_id,
        r.order_id,
        r.refund_timestamp,
        r.refund_date,
        r.refund_note,
        r.is_restock,
        r._extracted_at,
        -- Sum of all 'refund' transactions that succeeded
        coalesce((
            select sum(try_cast(t.value:amount as numeric(18,6)))
            from lateral flatten(input => r.refund_transactions, outer => true) t
            where lower(t.value:kind::varchar)   = 'refund'
              and lower(t.value:status::varchar) = 'success'
        ), 0)                                                           as refund_amount_local,
        -- Shipping refunded: from transactions where reason includes 'shipping'
        coalesce((
            select sum(try_cast(t.value:amount as numeric(18,6)))
            from lateral flatten(input => r.refund_transactions, outer => true) t
            where lower(t.value:kind::varchar)   = 'refund'
              and lower(t.value:status::varchar) = 'success'
              and lower(coalesce(t.value:reason::varchar, '')) like '%shipping%'
        ), 0)                                                           as refund_shipping_amount_local
    from {{ ref('stg_shopify__refunds') }} r
    where r.refund_id in (select refund_id from refunds)
),

-- Order context for order_sk, customer_sk, financial_status, fx_rate
order_ctx as (
    select
        order_id,
        order_sk,
        customer_sk,
        customer_id,
        net_amount,
        fx_rate_to_reporting,
        original_currency_code
    from {{ ref('fact_orders') }}
),

-- Stripe refund metadata (join via order → Stripe charge → Stripe refund)
stripe_ctx as (
    select
        sc.shopify_order_id                                             as order_id,
        lower(coalesce(sr.reason, ''))                                  as stripe_reason,
        lower(coalesce(sr.status, ''))                                  as stripe_status,
        sc.charge_id
    from {{ ref('stg_stripe__charges') }} sc
    left join {{ ref('stg_stripe__refunds') }} sr
        on sr.charge_id = sc.charge_id
    where sc.shopify_order_id is not null
    qualify row_number() over (
        partition by sc.shopify_order_id
        order by sc.charge_timestamp desc
    ) = 1
)

select
    {{ generate_dim_sk(['ra.refund_id']) }}                             as refund_sk,
    ra.refund_id,
    oc.order_sk,
    ra.order_id,
    oc.customer_sk,

    ra.refund_date,
    ra.refund_timestamp,

    -- refund_type: full vs. partial vs. chargeback
    case
        when abs(ra.refund_amount_local - oc.net_amount) < 0.01        then 'full_refund'
        when ra.refund_amount_local > 0                                 then 'partial_refund'
        else 'partial_refund'
    end                                                                 as refund_type,

    ra.refund_note                                                      as refund_reason,

    -- refund_category: keyword-based classification of refund_note (§4.21)
    case
        when lower(ra.refund_note) like '%damage%'
          or lower(ra.refund_note) like '%broken%'                      then 'damaged'
        when lower(ra.refund_note) like '%wrong%'
          or lower(ra.refund_note) like '%incorrect%'                   then 'wrong_item'
        when lower(ra.refund_note) like '%not as described%'
          or lower(ra.refund_note) like '%as described%'                then 'not_as_described'
        when lower(ra.refund_note) like '%changed%'
          or lower(ra.refund_note) like '%no longer%'
          or lower(ra.refund_note) like '%cancel%'                      then 'customer_change_of_mind'
        when lower(ra.refund_note) like '%quality%'
          or lower(ra.refund_note) like '%defect%'                      then 'quality_issue'
        when lower(ra.refund_note) like '%late%'
          or lower(ra.refund_note) like '%delay%'                       then 'late_delivery'
        else 'other'
    end                                                                 as refund_category,

    -- Monetary amounts in reporting currency
    cast(ra.refund_amount_local
         * coalesce(oc.fx_rate_to_reporting, 1.0) as numeric(18,4))    as refund_amount,
    -- Tax portion: approximated as 0 in v1 (line-level tax requires VARIANT unwinding)
    cast(0 as numeric(18,4))                                            as refund_tax_amount,
    cast(ra.refund_shipping_amount_local
         * coalesce(oc.fx_rate_to_reporting, 1.0) as numeric(18,4))    as refund_shipping_amount,
    cast(0 as numeric(18,4))                                            as restocking_fee,

    cast('{{ var("reporting_currency", "USD") }}' as varchar)           as currency_code,
    oc.original_currency_code,
    cast(ra.refund_amount_local as numeric(18,4))                       as original_refund_amount,

    -- Processor: 'stripe' when charge found; 'shopify' otherwise
    case
        when sc.charge_id is not null                                   then 'stripe'
        else 'shopify'
    end                                                                 as processor,

    -- Chargebacks: in v1, flag when Stripe reason is 'fraudulent'; coalesce guards NULL left join
    coalesce(sc.stripe_reason = 'fraudulent', false)                   as is_chargeback,

    cast(null as varchar)                                               as processed_by,
    ra.refund_note                                                      as note,

    ra.refund_timestamp                                                 as created_at,
    current_timestamp()                                                 as loaded_at,

    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='ra.refund_id',
        business_columns=['ra.refund_id', 'ra.order_id'],
        extracted_at_column='ra._extracted_at'
    ) }}

from refund_amounts ra
left join order_ctx oc
    on oc.order_id = ra.order_id
left join stripe_ctx sc
    on sc.order_id = ra.order_id
