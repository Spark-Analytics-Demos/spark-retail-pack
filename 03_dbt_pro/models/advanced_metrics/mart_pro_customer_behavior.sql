{{ config(materialized='table') }}

-- Pro Customer Behavior mart per Phase 2. KPIs 16, 17, 18.
-- Grain: one row per (date × channel_sk).
-- date = COALESCE(order_date, spend_date) — FULL OUTER JOIN handles spend-only dates.
-- KPI 16 §5.5 — Avg Time Between Orders: avg_days_between_orders per channel/day (aggregate monthly in Power BI).
-- KPI 17 §5.5 — CAC by Channel: spend_amount / NULLIF(new_customers, 0) in Power BI.
-- KPI 18 §5.5 — ROAS by Channel: net_revenue / NULLIF(spend_amount, 0) in Power BI.
-- Spend data: fact_marketing_spend covers Meta Ads (paid_social_meta) only in v1.
-- Attribution: last-touch — new customer channel = channel on first order (KPI 17).
-- avg_days_between_orders: only for repeat orders (first-order gaps are NULL by definition).

with order_daily as (
    select
        fo.order_date,
        fo.channel_sk,
        sum(fo.net_after_refunds)                                               as net_revenue,
        sum(fo.gross_amount)                                                    as gmv,
        count(distinct fo.order_id)                                             as order_count,
        -- KPI 17: new customers = first orders, attributed to the channel on that order
        count(distinct case when fo.is_first_order then fo.customer_id end)     as new_customers
    from {{ ref('fact_orders') }} fo
    where fo.order_status not in ('cancelled')
      and not fo.is_test_order
    group by fo.order_date, fo.channel_sk
),

spend_daily as (
    select
        fms.spend_date,
        fms.channel_sk,
        sum(fms.spend_amount)   as spend_amount,
        sum(fms.impressions)    as impressions,
        sum(fms.clicks)         as clicks
    from {{ ref('fact_marketing_spend') }} fms
    group by fms.spend_date, fms.channel_sk
),

-- KPI 16: inter-order gap per customer using LAG; aggregate to (order_date, channel_sk)
order_gaps as (
    select
        order_date,
        channel_sk,
        datediff('day',
            lag(order_date) over (partition by customer_id order by order_date),
            order_date
        ) as days_since_prev_order
    from {{ ref('fact_orders') }}
    where order_status not in ('cancelled')
      and not is_test_order
      and customer_id is not null
),

order_gaps_daily as (
    select
        order_date,
        channel_sk,
        avg(days_since_prev_order)                                              as avg_days_between_orders,
        count(1)                                                                as repeat_orders_with_gap
    from order_gaps
    where days_since_prev_order is not null
    group by order_date, channel_sk
),

-- Unified grain: FULL OUTER JOIN orders and spend
unified as (
    select
        coalesce(o.order_date,  s.spend_date)   as date,
        coalesce(o.channel_sk,  s.channel_sk)   as channel_sk,
        coalesce(o.net_revenue, 0)              as net_revenue,
        coalesce(o.gmv,         0)              as gmv,
        coalesce(o.order_count, 0)              as order_count,
        coalesce(o.new_customers, 0)            as new_customers,
        coalesce(s.spend_amount, 0)             as spend_amount,
        coalesce(s.impressions,  0)             as impressions,
        coalesce(s.clicks,       0)             as clicks
    from order_daily o
    full outer join spend_daily s
        on  s.spend_date = o.order_date
        and s.channel_sk = o.channel_sk
)

select
    {{ generate_dim_sk(['u.date', 'u.channel_sk']) }}                           as mart_pro_behavior_sk,

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

    -- KPI 17 — CAC: spend_amount / NULLIF(new_customers, 0) in Power BI
    u.new_customers,
    u.spend_amount,
    u.impressions,
    u.clicks,

    -- KPI 18 — ROAS: net_revenue / NULLIF(spend_amount, 0) in Power BI
    u.net_revenue,
    u.gmv,
    u.order_count,

    -- KPI 16 — Avg Time Between Orders: pre-computed per channel/day; aggregate weekly/monthly in Power BI
    og.avg_days_between_orders,
    og.repeat_orders_with_gap,

    current_timestamp()                                                         as loaded_at,

    {{ add_audit_columns(
        source_system='shopify',
        source_id_column="cast(u.date as varchar) || '|' || coalesce(cast(u.channel_sk as varchar), 'null')",
        business_columns=['u.date', 'u.channel_sk'],
        extracted_at_column='current_timestamp()'
    ) }}

from unified u
left join {{ ref('dim_date') }} dd
    on dd.date_sk = year(u.date) * 10000
                  + month(u.date) * 100
                  + day(u.date)
left join {{ ref('dim_channel') }} dc
    on dc.channel_sk = u.channel_sk
left join order_gaps_daily og
    on og.order_date = u.date
    and og.channel_sk = u.channel_sk
