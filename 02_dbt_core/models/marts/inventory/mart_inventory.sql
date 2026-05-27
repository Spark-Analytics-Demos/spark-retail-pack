{{ config(materialized='table') }}

-- OSS Inventory KPIs per Phase 2. Grain: one row per (snapshot_date × SKU × location).
-- KPI 20 §5.6 — Total Inventory Value: SUM(inventory_value) at desired grain in Power BI
-- KPI 22 §5.6 — Days of Supply: pre-computed in fact_inventory_snapshot; passed through
-- KPI 23 §5.6 — Stockout Rate: SUM(is_out_of_stock::int) / COUNT(*) in Power BI
-- KPIs 20 and 23 are NON-ADDITIVE across time (point-in-time snapshots).
-- Pro columns (is_low_stock, is_overstock, is_slow_mover) passed through as NULL in OSS.

select
    fis.inventory_snapshot_sk                                              as mart_inventory_sk,
    fis.snapshot_date,

    -- Date dimension attributes
    dd.date_sk,
    dd.month_number,
    dd.month_name,
    dd.quarter_number,
    dd.year,
    dd.is_mtd,
    dd.is_ytd,

    -- Product dimension attributes (slice KPIs by category, SKU, vendor)
    fis.product_sk,
    fis.sku,
    dp.display_name                                                        as product_display_name,
    dp.product_title,
    dp.category,
    dp.subcategory,
    dp.vendor,
    dp.is_active                                                           as product_is_active,

    -- Location dimension attributes
    fis.location_sk,
    dwl.location_name,
    dwl.location_type,
    dwl.country_code                                                       as location_country_code,

    -- Stock position
    fis.quantity_available,
    fis.quantity_on_hand,
    fis.quantity_incoming,
    fis.unit_cost,

    -- KPI 20 basis: SUM(inventory_value) at any grain in Power BI
    fis.inventory_value,

    -- KPI 22: Days of Supply (computed per SKU in fact_inventory_snapshot)
    fis.days_of_supply,

    -- KPI 23 basis: SUM(is_out_of_stock::int) / COUNT(*) in Power BI
    fis.is_out_of_stock,

    -- Pro columns — NULL in OSS per §11
    fis.is_low_stock,
    fis.is_overstock,
    fis.is_slow_mover,

    current_timestamp()                                                    as loaded_at,

    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='fis.inventory_snapshot_sk',
        business_columns=['fis.inventory_snapshot_sk'],
        extracted_at_column='current_timestamp()'
    ) }}

from {{ ref('fact_inventory_snapshot') }} fis
left join {{ ref('dim_date') }} dd
    on dd.date_sk = year(fis.snapshot_date) * 10000
                  + month(fis.snapshot_date) * 100
                  + day(fis.snapshot_date)
left join {{ ref('dim_product') }} dp
    on dp.product_sk = fis.product_sk
left join {{ ref('dim_warehouse_location') }} dwl
    on dwl.location_sk = fis.location_sk
