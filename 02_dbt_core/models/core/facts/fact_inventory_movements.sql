{{ config(
    materialized='incremental',
    incremental_strategy='append',
    unique_key='movement_id',
    on_schema_change='append_new_columns',
    cluster_by=['movement_date', 'product_sk']
) }}

-- fact_inventory_movements per §4.27. One row per inventory movement event.
-- v1 derives 'sale' and 'return' movements from fact_order_lines and fact_refunds.
-- location_sk: NULL in v1 — order lines do not carry fulfillment location.
--   Full location coverage requires Shopify Fulfillments API (stg_shopify__fulfillments).
-- receipt, adjustment, transfer, damaged, lost movements: add stg_shopify__inventory_adjustments
--   when the Fivetran/Airbyte inventory_adjustment_events table is available (Phase 2).
-- Lookback: applied at cutoff CTE level for both UNION branches.

{% set lookback_days = var('incremental_lookback_fact_inventory_movements_days',
                           var('incremental_lookback_days', 7)) %}

-- Compute incremental cutoff once (avoids duplicate subquery per UNION branch)
with cutoff as (
    {% if is_incremental() %}
    select dateadd('day', -{{ lookback_days }}, max(movement_date)) as cutoff_date
    from {{ this }}
    {% else %}
    select cast('1900-01-01' as date) as cutoff_date
    {% endif %}
),

sales as (
    select
        'sale_' || fol.line_item_id                                     as movement_id,
        fol.product_sk,
        fol.sku,
        cast(null as varchar)                                           as location_sk,
        fo.order_date                                                   as movement_date,
        fo.order_timestamp                                              as movement_timestamp,
        'sale'                                                          as movement_type,
        -- Quantity change: negative (stock decreases on sale)
        cast(-(fol.quantity - fol.refunded_quantity) as numeric(18,2)) as quantity_change,
        fol.unit_cost,
        cast(fol.unit_cost * (fol.quantity - fol.refunded_quantity)
             as numeric(18,4))                                          as movement_value,
        fo.order_id                                                     as reference_order_id,
        cast(null as varchar)                                           as reference_movement_id,
        cast(null as varchar)                                           as reason,
        cast(null as varchar)                                           as note,
        cast(null as varchar)                                           as created_by,
        fo._extracted_at
    from {{ ref('fact_order_lines') }} fol
    join {{ ref('fact_orders') }} fo
        on fo.order_id = fol.order_id
    cross join cutoff c
    where fo.order_status not in ('cancelled')
      and fo.order_date >= c.cutoff_date
      -- Only capture net-sold lines (exclude fully-refunded lines to avoid zero-qty noise)
      and (fol.quantity - fol.refunded_quantity) != 0
),

returns as (
    select
        -- Composite: one movement row per refunded line item (refund covers multiple lines)
        'return_' || fr.refund_id || '_' || fol.line_item_id            as movement_id,
        fol.product_sk,
        fol.sku,
        cast(null as varchar)                                           as location_sk,
        fr.refund_date                                                  as movement_date,
        fr.refund_timestamp                                             as movement_timestamp,
        'return'                                                        as movement_type,
        -- Quantity change: positive (stock increases on return)
        cast(fol.refunded_quantity as numeric(18,2))                    as quantity_change,
        fol.unit_cost,
        cast(fol.unit_cost * fol.refunded_quantity as numeric(18,4))   as movement_value,
        fr.order_id                                                     as reference_order_id,
        cast(null as varchar)                                           as reference_movement_id,
        fr.refund_reason                                                as reason,
        cast(null as varchar)                                           as note,
        cast(null as varchar)                                           as created_by,
        fr._extracted_at
    from {{ ref('fact_refunds') }} fr
    join {{ ref('fact_order_lines') }} fol
        on fol.order_id = fr.order_id
    cross join cutoff c
    where fol.refunded_quantity > 0
      and fr.refund_date >= c.cutoff_date
),

combined as (
    select * from sales
    union all
    select * from returns
)

select
    {{ generate_dim_sk(['movement_id']) }}                              as movement_sk,
    movement_id,
    product_sk,
    sku,
    location_sk,
    movement_date,
    movement_timestamp,
    movement_type,
    quantity_change,
    unit_cost,
    movement_value,
    reference_order_id,
    reference_movement_id,
    reason,
    note,
    created_by,
    current_timestamp()                                                 as loaded_at,

    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='movement_id',
        business_columns=['movement_id'],
        extracted_at_column='_extracted_at'
    ) }}

from combined
