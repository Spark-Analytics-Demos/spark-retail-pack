{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='line_item_id',
    on_schema_change='append_new_columns',
    cluster_by=['order_date', 'product_sk']
) }}

-- fact_order_lines per §4.20. One row per line item per order.
-- Joins fact_orders for order context (order_sk, customer_sk, channel_sk, order_date, fx_rate).
-- unit_cost: SCD2-aware lookup from dim_product at order_date.
-- refunded_quantity/amount: parsed from stg_shopify__refunds.refund_line_items VARIANT.
-- Discount allocation: order-level discounts already allocated at the staging layer (total_discount).

with line_items as (
    select * from {{ ref('stg_shopify__order_line_items') }}
    {{ incremental_lookback('_loaded_at', 'fact_order_lines') }}
),

-- Order context: FX rate, surrogate key, customer, channel, date
order_context as (
    select
        order_id,
        order_sk,
        customer_sk,
        customer_id,
        channel_sk,
        order_date,
        order_timestamp,
        fx_rate_to_reporting
    from {{ ref('fact_orders') }}
),

-- Line-level refund quantities and amounts from Shopify refund_line_items VARIANT
refund_lines as (
    select
        r.order_id,
        f.value:line_item_id::varchar                                   as line_item_id,
        sum(try_cast(f.value:quantity::varchar as numeric(18,2)))       as refunded_quantity,
        sum(try_cast(f.value:subtotal::varchar as numeric(18,6)))       as refunded_amount_local
    from {{ ref('stg_shopify__refunds') }} r,
    lateral flatten(input => r.refund_line_items, outer => true) f
    where f.value:line_item_id is not null
    group by r.order_id, f.value:line_item_id::varchar
),

-- Product SK: SCD2-aware — dim version active at order_date
product_lookup as (
    select
        sku,
        variant_id,
        product_sk,
        unit_cost,
        valid_from,
        valid_to
    from {{ ref('dim_product') }}
)

select
    {{ generate_dim_sk(['l.line_item_id']) }}                           as line_item_sk,
    l.line_item_id,

    -- Order FKs (denormalized from fact_orders)
    oc.order_sk,
    l.order_id,
    oc.customer_sk,
    dp.product_sk,
    l.sku,
    l.product_title_at_sale,
    oc.channel_sk,
    oc.order_date,

    -- Quantities and amounts (already in Shopify store currency at staging)
    cast(l.quantity         as numeric(18,2))                           as quantity,
    cast(l.unit_price       as numeric(18,4))                           as unit_price,
    cast(dp.unit_cost       as numeric(18,4))                           as unit_cost,
    cast(l.line_subtotal    * coalesce(oc.fx_rate_to_reporting, 1.0)
                            as numeric(18,4))                           as line_subtotal,
    cast(l.line_discount    * coalesce(oc.fx_rate_to_reporting, 1.0)
                            as numeric(18,4))                           as line_discount,
    cast(l.line_tax         * coalesce(oc.fx_rate_to_reporting, 1.0)
                            as numeric(18,4))                           as line_tax,
    cast(l.line_net_amount  * coalesce(oc.fx_rate_to_reporting, 1.0)
                            as numeric(18,4))                           as line_net_amount,

    -- Gross margin: line_net_amount - (quantity * unit_cost); NULL when cost not tracked
    case
        when dp.unit_cost is not null
            then cast(
                (l.line_net_amount - l.quantity * dp.unit_cost)
                * coalesce(oc.fx_rate_to_reporting, 1.0)
                as numeric(18,4)
            )
    end                                                                 as line_gross_margin,

    l.was_promotional,

    -- Refund columns (line-level, from refund_line_items VARIANT)
    cast(coalesce(rl.refunded_quantity,    0) as numeric(18,2))         as refunded_quantity,
    cast(coalesce(rl.refunded_amount_local, 0)
         * coalesce(oc.fx_rate_to_reporting, 1.0) as numeric(18,4))    as refunded_amount,
    coalesce(rl.refunded_quantity, 0) > 0                               as is_returned,

    -- Reporting currency
    cast('{{ var("reporting_currency", "USD") }}' as varchar)           as currency_code,

    oc.order_timestamp                                                  as created_at,
    current_timestamp()                                                 as loaded_at,

    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='l.line_item_id',
        business_columns=['l.line_item_id', 'l.order_id'],
        extracted_at_column='l._extracted_at'
    ) }}

from line_items l
-- Order context (already built; contains fx_rate_to_reporting)
left join order_context oc
    on oc.order_id = l.order_id
-- SCD2-aware product lookup: dim version effective at order_date
left join product_lookup dp
    on dp.sku = l.sku
    and oc.order_date >= dp.valid_from::date
    and (oc.order_date < dp.valid_to::date or dp.valid_to is null)
-- Line-level refund detail
left join refund_lines rl
    on rl.line_item_id = l.line_item_id
