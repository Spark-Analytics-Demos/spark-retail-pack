{{ config(materialized='table') }}

-- Pro Sales mart per Phase 2. KPIs 6 & 8.
-- Grain: one row per (date × channel_sk × geography_sk).
-- date = COALESCE(order_date, refund_date): refund amounts attributed to refund_date (§5.4 note).
-- KPI 6 §5.4 — Refund Rate: SUM(total_refund_amount) / NULLIF(SUM(gmv), 0) * 100 in Power BI.
-- KPI 8 §5.4 — Revenue by Channel: SUM(net_revenue) sliced by channel_name in Power BI.
-- Excludes cancelled and test orders. Refund channel/geography inherited from originating order.

with order_daily as (
    select
        fo.order_date,
        fo.channel_sk,
        fo.geography_sk,
        sum(fo.gross_amount)                                                as gmv,
        sum(fo.net_after_refunds)                                           as net_revenue,
        count(distinct fo.order_id)                                         as order_count
    from {{ ref('fact_orders') }} fo
    where fo.order_status not in ('cancelled')
      and not fo.is_test_order
    group by fo.order_date, fo.channel_sk, fo.geography_sk
),

-- Refunds attributed to refund_date; channel and geography inherited from originating order
refund_daily as (
    select
        fr.refund_date,
        fo.channel_sk,
        fo.geography_sk,
        sum(fr.refund_amount)                                               as total_refund_amount,
        count(distinct fr.refund_id)                                        as refund_count
    from {{ ref('fact_refunds') }} fr
    left join {{ ref('fact_orders') }} fo
        on fo.order_sk = fr.order_sk
    group by fr.refund_date, fo.channel_sk, fo.geography_sk
),

-- Unified grain: FULL OUTER JOIN on (date, channel_sk, geography_sk)
unified as (
    select
        coalesce(o.order_date,   r.refund_date)    as date,
        coalesce(o.channel_sk,   r.channel_sk)     as channel_sk,
        coalesce(o.geography_sk, r.geography_sk)   as geography_sk,
        coalesce(o.gmv,          0)                as gmv,
        coalesce(o.net_revenue,  0)                as net_revenue,
        coalesce(o.order_count,  0)                as order_count,
        coalesce(r.total_refund_amount, 0)         as total_refund_amount,
        coalesce(r.refund_count, 0)                as refund_count
    from order_daily o
    full outer join refund_daily r
        on  r.refund_date  = o.order_date
        and r.channel_sk   = o.channel_sk
        and r.geography_sk = o.geography_sk
)

select
    {{ generate_dim_sk(['u.date', 'u.channel_sk', 'u.geography_sk']) }}     as mart_pro_sales_sk,

    u.date,
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
    dd.is_mtd,
    dd.is_qtd,
    dd.is_ytd,

    u.channel_sk,
    dc.channel_name,
    dc.channel_category,
    dc.channel_type,
    dc.is_paid,

    u.geography_sk,
    dg.country_code,
    dg.country_name,
    dg.country_region,

    -- KPI 8 — Revenue by Channel: SUM(net_revenue) GROUP BY channel_name in Power BI
    u.gmv,
    u.net_revenue,
    u.order_count,

    -- KPI 6 — Refund Rate components: SUM(total_refund_amount) / NULLIF(SUM(gmv), 0) * 100 in Power BI
    u.total_refund_amount,
    u.refund_count,

    current_timestamp()                                                     as loaded_at,

    {{ add_audit_columns(
        source_system='shopify',
        source_id_column="cast(u.date as varchar) || '|' || coalesce(cast(u.channel_sk as varchar), 'null') || '|' || coalesce(cast(u.geography_sk as varchar), 'null')",
        business_columns=['u.date', 'u.channel_sk', 'u.geography_sk'],
        extracted_at_column='current_timestamp()'
    ) }}

from unified u
left join {{ ref('dim_date') }} dd
    on dd.date_sk = year(u.date) * 10000
                  + month(u.date) * 100
                  + day(u.date)
left join {{ ref('dim_channel') }} dc
    on dc.channel_sk = u.channel_sk
left join {{ ref('dim_geography') }} dg
    on dg.geography_sk = u.geography_sk
