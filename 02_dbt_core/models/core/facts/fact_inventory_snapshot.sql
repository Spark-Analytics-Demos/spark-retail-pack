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
--
-- DEMO backfill (var backfill_snapshots=true, see dbt_project.yml): also emit a month-end
-- snapshot for every month in the order history so Inventory Value / Days of Supply have a
-- real trend. Historical on-hand is RECONSTRUCTED from movement history:
--   on_hand(D) = final_available - SUM(quantity_change WHERE movement_date > D)
-- and days_of_supply uses the trailing-28d sales ending at each snapshot_date. current_date()
-- is always included so the recency test still passes. Prod/default stays today-only.

-- Snapshot coverage modes (most → least history):
--   use_daily_snapshot_history : one real snapshot per day from the daily feed
--     (stg_shopify__inventory_snapshots) — drives the Inventory Health trends.
--   backfill_snapshots         : reconstructed month-end snapshots from movements.
--   default                    : today only (prod / real-client safe).
-- Vars arrive as the string 'True'/'False' (target-aware default in dbt_project.yml) or a
-- real bool (--vars); normalise so 'False' isn't treated as truthy.
{% set use_daily = (var('use_daily_snapshot_history', false) | string | lower == 'true') %}
{% set backfill = (var('backfill_snapshots', false) | string | lower == 'true') %}
{% set per_day = use_daily or backfill %}

with snapshot_date_cte as (
{% if use_daily %}
    select distinct snapshot_date from {{ ref('stg_shopify__inventory_snapshots') }}
{% elif backfill %}
    select distinct dd.month_ending_date as snapshot_date
    from {{ ref('dim_date') }} dd
    where dd.month_ending_date between
            (select min(order_date) from {{ ref('fact_order_lines') }})
        and (select max(order_date) from {{ ref('fact_order_lines') }})
    union
    select current_date()
{% else %}
    select current_date() as snapshot_date
{% endif %}
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

-- Stock position AS-OF each snapshot_date.
-- Daily history: take the real per-day on-hand straight from the daily feed.
-- Default: the current Shopify level (one snapshot = today).
-- Backfill: reconstruct historical on-hand by removing net movements that happened AFTER
-- the snapshot date — on_hand(D) = final_available - SUM(quantity_change WHERE date > D).
positions as (
{% if use_daily %}
    select
        s.inventory_item_id,
        s.location_id,
        ii.sku,
        ii.unit_cost,
        s.quantity_incoming,
        s.updated_at                                                    as _extracted_at,
        s.snapshot_date,
        cast(s.quantity_available as numeric(18,2))                     as quantity_available
    from {{ ref('stg_shopify__inventory_snapshots') }} s
    left join {{ ref('stg_shopify__inventory_items') }} ii
        on ii.inventory_item_id = s.inventory_item_id
{% else %}
    select
        i.inventory_item_id,
        i.location_id,
        i.sku,
        i.unit_cost,
        i.quantity_incoming,
        i._extracted_at,
        sd.snapshot_date,
{% if backfill %}
        greatest(
            0,
            cast(i.quantity_available - coalesce(mv.qty_change_after, 0) as numeric(18,2))
        )                                                               as quantity_available
{% else %}
        cast(i.quantity_available as numeric(18,2))                     as quantity_available
{% endif %}
    from inventory i
    cross join snapshot_date_cte sd
{% if backfill %}
    left join (
        select
            m.sku,
            s.snapshot_date,
            sum(m.quantity_change)                                      as qty_change_after
        from {{ ref('fact_inventory_movements') }} m
        cross join snapshot_date_cte s
        where m.movement_date > s.snapshot_date
        group by m.sku, s.snapshot_date
    ) mv
        on mv.sku = i.sku
        and mv.snapshot_date = sd.snapshot_date
{% endif %}
{% endif %}
),

-- Average daily units sold over the trailing 28 days ending at each snapshot_date.
avg_daily_sales as (
{% if per_day %}
    select
        ol.sku,
        s.snapshot_date,
        sum(ol.quantity - ol.refunded_quantity) / 28.0                  as avg_daily_units_28d
    from {{ ref('fact_order_lines') }} ol
    cross join snapshot_date_cte s
    where ol.order_date >= dateadd('day', -28, s.snapshot_date)
      and ol.order_date <  s.snapshot_date
      and ol.sku is not null
    group by ol.sku, s.snapshot_date
{% else %}
    select
        sku,
        current_date()                                                 as snapshot_date,
        sum(quantity - refunded_quantity) / 28.0                        as avg_daily_units_28d
    from {{ ref('fact_order_lines') }}
    where order_date >= dateadd('day', -28, current_date())
      and order_date <  current_date()
      and sku is not null
    group by sku
{% endif %}
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
    {{ generate_dim_sk(['i.inventory_item_id', 'i.location_id', 'i.snapshot_date']) }}
                                                                        as inventory_snapshot_sk,
    dp.product_sk,
    i.sku,
    dl.location_sk,
    i.inventory_item_id,
    i.location_id,
    i.snapshot_date,

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
        source_id_column="i.inventory_item_id || '_' || i.location_id || '_' || cast(i.snapshot_date as varchar)",
        business_columns=['i.inventory_item_id', 'i.location_id', 'i.snapshot_date'],
        extracted_at_column='i._extracted_at'
    ) }}

from positions i
left join product_sk_lookup dp
    on dp.sku = i.sku
left join location_sk_lookup dl
    on dl.location_id = i.location_id
left join avg_daily_sales ads
    on ads.sku = i.sku
{% if per_day %}
    and ads.snapshot_date = i.snapshot_date
{% endif %}
