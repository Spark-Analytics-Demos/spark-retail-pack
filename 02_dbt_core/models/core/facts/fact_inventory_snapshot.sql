{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['inventory_item_id', 'location_id', 'snapshot_date'],
    on_schema_change='append_new_columns',
    cluster_by=['snapshot_date', 'product_sk', 'location_sk']
) }}

-- fact_inventory_snapshot per §4.26. One row per SKU per location per day.
-- Source: stg_shopify__inventory_levels (quantity_available, quantity_incoming) joined
--   to stg_shopify__inventory_items (sku, unit_cost).
-- Pattern: daily snapshot of current Shopify inventory state.
--   Incremental: MERGE on (inventory_item_id, location_id, snapshot_date) — idempotent.
-- quantity_on_hand: approximated as quantity_available (Shopify exposes available = on_hand - committed).
--   quantity_committed: NULL in v1 — requires open-order committed count not in connector scope.
-- days_of_supply: quantity_available / avg daily sold quantity over trailing 28 days (from fact_order_lines).
-- OSS columns: 1-14 (stock position, value, basic OOS flag).
-- Pro columns 15-17 (is_low_stock, is_overstock, is_slow_mover) — NULL in OSS per §11.

with snapshot_date_cte as (
    select current_date() as snapshot_date
),

inventory as (
    select
        il.inventory_item_id,
        il.location_id,
        il.quantity_available,
        il.quantity_incoming,
        il.updated_at                                                   as _extracted_at,
        ii.sku,
        ii.unit_cost
    from {{ ref('stg_shopify__inventory_levels') }} il
    left join {{ ref('stg_shopify__inventory_items') }} ii
        on ii.inventory_item_id = il.inventory_item_id
),

-- Average daily units sold per SKU over trailing 28 days (for days_of_supply)
avg_daily_sales as (
    select
        sku,
        -- sold units: quantity - refunded_quantity (net units sold and kept)
        sum(quantity - refunded_quantity) / 28.0                        as avg_daily_units_28d
    from {{ ref('fact_order_lines') }}
    where order_date >= dateadd('day', -28, current_date())
      and order_date <  current_date()
      and sku is not null
    group by sku
),

-- Current product SK (SCD2 current version, by SKU)
product_sk_lookup as (
    select sku, product_sk
    from {{ ref('dim_product') }}
    where is_current = true
),

-- Location SK
location_sk_lookup as (
    select location_id, location_sk
    from {{ ref('dim_warehouse_location') }}
)

select
    {{ generate_dim_sk(['i.inventory_item_id', 'i.location_id', 'sd.snapshot_date']) }}
                                                                        as inventory_snapshot_sk,
    dp.product_sk,
    i.sku,
    dl.location_sk,
    i.inventory_item_id,
    i.location_id,
    sd.snapshot_date,

    -- Stock quantities
    -- Shopify available = on_hand - committed; used as best approximation for on_hand in v1
    cast(i.quantity_available as numeric(18,2))                         as quantity_on_hand,
    cast(null as numeric(18,2))                                         as quantity_committed,
    cast(i.quantity_available as numeric(18,2))                         as quantity_available,
    cast(i.quantity_incoming  as numeric(18,2))                         as quantity_incoming,

    -- Cost and value
    cast(i.unit_cost as numeric(18,4))                                  as unit_cost,
    case
        when i.unit_cost is not null
            then cast(i.quantity_available * i.unit_cost as numeric(18,4))
    end                                                                 as inventory_value,

    -- Days of supply: available quantity / avg daily sales rate
    case
        when coalesce(ads.avg_daily_units_28d, 0) > 0
            then cast(i.quantity_available / ads.avg_daily_units_28d as numeric(18,2))
    end                                                                 as days_of_supply,

    -- OOS flag
    i.quantity_available <= 0                                           as is_out_of_stock,

    -- Pro columns — NULL in OSS per §11
    cast(null as boolean)                                               as is_low_stock,
    cast(null as boolean)                                               as is_overstock,
    cast(null as boolean)                                               as is_slow_mover,

    current_timestamp()                                                 as loaded_at,

    {{ add_audit_columns(
        source_system='shopify',
        source_id_column="i.inventory_item_id || '_' || i.location_id || '_' || cast(sd.snapshot_date as varchar)",
        business_columns=['i.inventory_item_id', 'i.location_id', 'sd.snapshot_date'],
        extracted_at_column='i._extracted_at'
    ) }}

from inventory i
cross join snapshot_date_cte sd
left join product_sk_lookup dp
    on dp.sku = i.sku
left join location_sk_lookup dl
    on dl.location_id = i.location_id
left join avg_daily_sales ads
    on ads.sku = i.sku
