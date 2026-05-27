{{ config(materialized='table') }}

-- Pro Returns mart per Phase 2. KPI 7 §5.4 — Return Rate.
-- Grain: one row per (order_date × product_sk × channel_sk × geography_sk).
-- KPI 7: SUM(total_refunded_quantity) / NULLIF(SUM(total_quantity), 0) * 100 in Power BI.
-- Slicers: Product, Category, Channel, Geography.
-- geography_sk joined from fact_orders (not available directly in fact_order_lines).
-- Excludes cancelled and test orders.

with line_items as (
    select
        fol.order_date,
        fol.product_sk,
        fol.sku,
        fol.channel_sk,
        fo.geography_sk,
        cast(fol.quantity           as numeric(18,2)) as quantity,
        cast(fol.refunded_quantity  as numeric(18,2)) as refunded_quantity,
        fol.line_net_amount,
        fol.refunded_amount,
        fol.is_returned
    from {{ ref('fact_order_lines') }} fol
    left join {{ ref('fact_orders') }} fo
        on fo.order_sk = fol.order_sk
    where fo.order_status not in ('cancelled')
      and not fo.is_test_order
),

daily_product as (
    select
        order_date,
        product_sk,
        channel_sk,
        geography_sk,
        sum(quantity)                                                           as total_quantity,
        sum(refunded_quantity)                                                  as total_refunded_quantity,
        sum(line_net_amount)                                                    as total_line_revenue,
        sum(refunded_amount)                                                    as total_refunded_revenue,
        sum(case when is_returned then 1 else 0 end)                           as returned_line_count,
        count(1)                                                                as total_line_count
    from line_items
    group by order_date, product_sk, channel_sk, geography_sk
)

select
    {{ generate_dim_sk(['dprod.order_date', 'dprod.product_sk', 'dprod.channel_sk', 'dprod.geography_sk']) }}
                                                                                as mart_pro_returns_sk,

    dprod.order_date,
    dd.date_sk,
    dd.week_of_year,
    dd.month_number,
    dd.month_name,
    dd.quarter_number,
    dd.year,
    dd.is_mtd,
    dd.is_ytd,

    dprod.product_sk,
    dp.display_name                                                             as product_display_name,
    dp.product_title,
    dp.category,
    dp.subcategory,
    dp.vendor,
    dp.is_active                                                                as product_is_active,

    dprod.channel_sk,
    dc.channel_name,
    dc.channel_category,
    dc.channel_type,
    dc.is_paid,

    dprod.geography_sk,
    dg.country_code,
    dg.country_name,
    dg.country_region,

    -- KPI 7 — Return Rate components: SUM(total_refunded_quantity) / NULLIF(SUM(total_quantity), 0) * 100
    dprod.total_quantity,
    dprod.total_refunded_quantity,
    dprod.total_line_revenue,
    dprod.total_refunded_revenue,
    dprod.returned_line_count,
    dprod.total_line_count,

    current_timestamp()                                                         as loaded_at,

    {{ add_audit_columns(
        source_system='shopify',
        source_id_column="cast(dprod.order_date as varchar) || '|' || coalesce(cast(dprod.product_sk as varchar), 'null') || '|' || coalesce(cast(dprod.channel_sk as varchar), 'null') || '|' || coalesce(cast(dprod.geography_sk as varchar), 'null')",
        business_columns=['dprod.order_date', 'dprod.product_sk', 'dprod.channel_sk'],
        extracted_at_column='current_timestamp()'
    ) }}

from daily_product dprod
left join {{ ref('dim_date') }} dd
    on dd.date_sk = year(dprod.order_date) * 10000
                  + month(dprod.order_date) * 100
                  + day(dprod.order_date)
left join {{ ref('dim_product') }} dp
    on dp.product_sk = dprod.product_sk
left join {{ ref('dim_channel') }} dc
    on dc.channel_sk = dprod.channel_sk
left join {{ ref('dim_geography') }} dg
    on dg.geography_sk = dprod.geography_sk
