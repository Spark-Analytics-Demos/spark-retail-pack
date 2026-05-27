{{ config(materialized='table') }}

-- Pro Inventory mart per Phase 2. KPIs 21, 24, 25.
-- Grain: one row per (snapshot_date × product_sk × location_sk). Same grain as mart_inventory.
-- Extends mart_inventory with actual Pro flag values (not NULL as in OSS) and trailing metrics.
-- KPI 21 §5.6 — Inventory Turnover: cogs_last_30d / NULLIF(inventory_value, 0) * 12 in Power BI.
-- KPI 24 §5.6 — Sell-Through Rate (v1 proxy): sell_through_rate_30d / sell_through_rate_60d.
--   v1 limitation: proxy uses quantity_available as units_remaining; cohort receipt logic in v2.
-- KPI 25 §5.6 — Slow-Moving SKU Count: COUNT(is_slow_mover=TRUE) at snapshot_date in Power BI.
-- Trailing metrics (units_sold_*, cogs_*) computed at SKU level (location-agnostic in v1).
-- Pro flags:
--   is_low_stock  — days_of_supply in (0, 14) (has velocity + limited stock)
--   is_overstock  — days_of_supply > 90
--   is_slow_mover — no net sales in trailing 60 days (KPI 25 basis)

with inventory as (
    select
        fis.inventory_snapshot_sk,
        fis.product_sk,
        fis.sku,
        fis.location_sk,
        fis.inventory_item_id,
        fis.location_id,
        fis.snapshot_date,
        fis.quantity_available,
        fis.quantity_on_hand,
        fis.quantity_incoming,
        fis.unit_cost,
        fis.inventory_value,
        fis.days_of_supply,
        fis.is_out_of_stock
    from {{ ref('fact_inventory_snapshot') }} fis
),

-- Trailing net units sold and COGS per SKU over 30 / 60 / 90 day windows.
-- Location-agnostic: fact_order_lines lacks location_sk in v1.
-- Relative to current_date() — valid because mart is rebuilt daily.
trailing_sales as (
    select
        sku,
        sum(case when order_date >= dateadd('day', -30, current_date())
                 then greatest(cast(quantity - refunded_quantity as numeric(18,2)), 0)
                 else 0 end)                                                as units_sold_30d,
        sum(case when order_date >= dateadd('day', -60, current_date())
                 then greatest(cast(quantity - refunded_quantity as numeric(18,2)), 0)
                 else 0 end)                                                as units_sold_60d,
        sum(case when order_date >= dateadd('day', -90, current_date())
                 then greatest(cast(quantity - refunded_quantity as numeric(18,2)), 0)
                 else 0 end)                                                as units_sold_90d,
        -- COGS: NULL propagated when unit_cost not tracked for any line in the window
        sum(case when order_date >= dateadd('day', -30, current_date())
                      and unit_cost is not null
                 then greatest(cast(quantity - refunded_quantity as numeric(18,2)), 0) * unit_cost
                 else null end)                                             as cogs_30d,
        sum(case when order_date >= dateadd('day', -90, current_date())
                      and unit_cost is not null
                 then greatest(cast(quantity - refunded_quantity as numeric(18,2)), 0) * unit_cost
                 else null end)                                             as cogs_90d
    from {{ ref('fact_order_lines') }}
    where order_date >= dateadd('day', -90, current_date())
      and sku is not null
    group by sku
)

select
    i.inventory_snapshot_sk                                                 as mart_pro_inventory_sk,
    i.snapshot_date,

    -- Date dimension attributes
    dd.date_sk,
    dd.month_number,
    dd.month_name,
    dd.quarter_number,
    dd.year,
    dd.is_mtd,
    dd.is_ytd,

    -- Product dimension attributes
    i.product_sk,
    i.sku,
    dp.display_name                                                         as product_display_name,
    dp.product_title,
    dp.category,
    dp.subcategory,
    dp.vendor,
    dp.is_active                                                            as product_is_active,

    -- Location dimension attributes
    i.location_sk,
    dwl.location_name,
    dwl.location_type,
    dwl.country_code                                                        as location_country_code,

    -- Stock position (from OSS fact)
    i.quantity_available,
    i.quantity_on_hand,
    i.quantity_incoming,
    i.unit_cost,
    i.inventory_value,
    i.days_of_supply,
    i.is_out_of_stock,

    -- Pro flags (actual computed values; OSS passes these as NULL)
    -- is_low_stock: has velocity (days_of_supply known) AND will stock out within 14 days
    (i.days_of_supply is not null and i.days_of_supply > 0 and i.days_of_supply < 14)
                                                                            as is_low_stock,
    -- is_overstock: has velocity AND stock will last more than 90 days
    (i.days_of_supply is not null and i.days_of_supply > 90)               as is_overstock,
    -- is_slow_mover: no net sales in trailing 60 days (KPI 25 basis)
    coalesce(ts.units_sold_60d, 0) = 0                                     as is_slow_mover,

    -- Trailing sales metrics (SKU-level; location-agnostic in v1)
    coalesce(ts.units_sold_30d, 0)                                         as units_sold_30d,
    coalesce(ts.units_sold_60d, 0)                                         as units_sold_60d,
    coalesce(ts.units_sold_90d, 0)                                         as units_sold_90d,

    -- KPI 21 — Inventory Turnover components (Power BI: cogs_last_30d / NULLIF(inventory_value, 0) * 12)
    ts.cogs_30d                                                             as cogs_last_30d,
    ts.cogs_90d                                                             as cogs_last_90d,

    -- KPI 24 — Sell-Through Rate v1 proxy (true cohort requires receipt data; Phase 2 v2)
    -- sell_through_rate_30d = units_sold_30d / (units_sold_30d + quantity_available) * 100
    case
        when coalesce(ts.units_sold_30d, 0) + greatest(i.quantity_available, 0) > 0
            then cast(
                100.0 * coalesce(ts.units_sold_30d, 0)
                / (coalesce(ts.units_sold_30d, 0) + greatest(i.quantity_available, 0))
                as numeric(8,4)
            )
    end                                                                     as sell_through_rate_30d,
    case
        when coalesce(ts.units_sold_60d, 0) + greatest(i.quantity_available, 0) > 0
            then cast(
                100.0 * coalesce(ts.units_sold_60d, 0)
                / (coalesce(ts.units_sold_60d, 0) + greatest(i.quantity_available, 0))
                as numeric(8,4)
            )
    end                                                                     as sell_through_rate_60d,

    current_timestamp()                                                     as loaded_at,

    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='i.inventory_snapshot_sk',
        business_columns=['i.inventory_snapshot_sk'],
        extracted_at_column='current_timestamp()'
    ) }}

from inventory i
left join {{ ref('dim_date') }} dd
    on dd.date_sk = year(i.snapshot_date) * 10000
                  + month(i.snapshot_date) * 100
                  + day(i.snapshot_date)
left join {{ ref('dim_product') }} dp
    on dp.product_sk = i.product_sk
left join {{ ref('dim_warehouse_location') }} dwl
    on dwl.location_sk = i.location_sk
left join trailing_sales ts
    on ts.sku = i.sku
