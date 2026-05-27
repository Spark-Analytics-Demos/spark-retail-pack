{{ config(materialized='table') }}

-- OSS Sales KPIs per Phase 2. Grain: one row per (order_date × channel × geography).
-- KPI 1  §5.4 — GMV: SUM(gross_amount) on non-cancelled, non-test orders
-- KPI 2  §5.4 — Net Revenue: SUM(gross - discount - refunded)
-- KPI 3  §5.4 — Order Count: COUNT(DISTINCT order_id)
-- KPI 9  §5.4 — Tax Collected: SUM(tax_amount)
-- KPI 12 §5.5 — New Customers per day: COUNT DISTINCT WHERE is_first_order
-- KPI 13 §5.5 — Repeat Customer Count: COUNT DISTINCT WHERE is_repeat_order
-- KPI 4/5/14 are ratio/derived — compute in Power BI or semantic layer, not pre-aggregated.

with orders as (
    select
        fo.order_date,
        fo.channel_sk,
        fo.geography_sk,
        fo.order_id,
        fo.customer_sk,
        fo.gross_amount,
        fo.discount_amount,
        fo.tax_amount,
        fo.shipping_amount,
        fo.refunded_amount,
        fo.is_first_order,
        fo.is_repeat_order
    from {{ ref('fact_orders') }} fo
    where fo.order_status not in ('cancelled')
      and not fo.is_test_order
),

daily as (
    select
        o.order_date,
        o.channel_sk,
        o.geography_sk,
        -- KPI 1
        sum(o.gross_amount)                                                  as gmv,
        -- KPI 2
        sum(o.gross_amount - o.discount_amount - o.refunded_amount)          as net_revenue,
        -- KPI 3
        count(distinct o.order_id)                                           as order_count,
        -- KPI 9
        sum(o.tax_amount)                                                    as tax_collected,
        -- KPI 12
        count(distinct case when o.is_first_order  then o.customer_sk end)   as new_customers,
        -- KPI 13
        count(distinct case when o.is_repeat_order then o.customer_sk end)   as repeat_customers,
        -- Supplementary
        count(distinct o.customer_sk)                                        as unique_customers,
        sum(o.discount_amount)                                               as total_discounts,
        sum(o.shipping_amount)                                               as shipping_revenue,
        sum(o.refunded_amount)                                               as total_refunds
    from orders o
    group by 1, 2, 3
)

select
    {{ generate_dim_sk(['d.order_date', 'd.channel_sk', 'd.geography_sk']) }} as mart_sales_sk,

    -- Date
    d.order_date,
    dd.date_sk,
    dd.week_starting_date,
    dd.week_of_year,
    dd.month_number,
    dd.month_name,
    dd.month_short_name,
    dd.quarter_number,
    dd.quarter_name,
    dd.year,
    dd.is_weekend,
    dd.is_business_day,
    dd.is_holiday,
    dd.is_mtd,
    dd.is_qtd,
    dd.is_ytd,

    -- Channel
    d.channel_sk,
    dc.channel_name,
    dc.channel_category,
    dc.channel_type,
    dc.is_paid,

    -- Geography
    d.geography_sk,
    dg.country_code,
    dg.country_name,
    dg.country_region,

    -- KPI 1: GMV
    d.gmv,
    -- KPI 2: Net Revenue
    d.net_revenue,
    -- KPI 3: Order Count
    d.order_count,
    -- KPI 9: Tax Collected
    d.tax_collected,
    -- KPI 12: New Customers
    d.new_customers,
    -- KPI 13: Repeat Customers (KPI 14 = repeat_customers / (new_customers + repeat_customers))
    d.repeat_customers,
    -- Supplementary
    d.unique_customers,
    d.total_discounts,
    d.shipping_revenue,
    d.total_refunds,

    current_timestamp()                                                      as loaded_at,

    {{ add_audit_columns(
        source_system='shopify',
        source_id_column="cast(d.order_date as varchar) || '|' || coalesce(cast(d.channel_sk as varchar), 'null') || '|' || coalesce(cast(d.geography_sk as varchar), 'null')",
        business_columns=['d.order_date', 'd.channel_sk', 'd.geography_sk'],
        extracted_at_column='current_timestamp()'
    ) }}

from daily d
left join {{ ref('dim_date') }} dd
    on dd.date_sk = year(d.order_date) * 10000
                  + month(d.order_date) * 100
                  + day(d.order_date)
left join {{ ref('dim_channel') }} dc
    on dc.channel_sk = d.channel_sk
left join {{ ref('dim_geography') }} dg
    on dg.geography_sk = d.geography_sk
