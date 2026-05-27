{{ config(materialized='table') }}

-- OSS Customer KPIs per Phase 2. Grain: one row per snapshot_date.
-- KPI 10 §5.5 — Active Customers 30d: COUNT DISTINCT WHERE is_active_30d = TRUE
-- KPI 11 §5.5 — Active Customers 90d: COUNT DISTINCT WHERE is_active_90d = TRUE
-- WARNING: active_customers_30d and active_customers_90d are NON-ADDITIVE across time.
--          Do not SUM across snapshot_dates. Use a single snapshot_date filter in Power BI.
-- KPIs 12-14 (new/repeat customers, repeat purchase rate) are in mart_sales — they
-- are order-flow metrics aggregated by order_date, not customer-state snapshots.

with customer_state as (
    select
        snapshot_date,
        customer_id,
        is_active_30d,
        is_active_90d,
        is_new_30d,
        is_repeat_customer,
        lifetime_order_count,
        lifetime_revenue,
        trailing_30d_revenue,
        trailing_90d_revenue
    from {{ ref('fact_customer_state_daily') }}
),

daily_counts as (
    select
        snapshot_date,
        -- KPI 10
        count(distinct case when is_active_30d      then customer_id end)  as active_customers_30d,
        -- KPI 11
        count(distinct case when is_active_90d      then customer_id end)  as active_customers_90d,
        -- Supplementary
        count(distinct customer_id)                                         as total_tracked_customers,
        count(distinct case when is_new_30d         then customer_id end)  as new_in_30d_window,
        count(distinct case when is_repeat_customer then customer_id end)  as repeat_customers,
        avg(lifetime_revenue)                                               as avg_lifetime_revenue,
        avg(lifetime_order_count)                                           as avg_lifetime_orders,
        sum(trailing_30d_revenue)                                           as total_trailing_30d_revenue,
        sum(trailing_90d_revenue)                                           as total_trailing_90d_revenue
    from customer_state
    group by snapshot_date
)

select
    {{ generate_dim_sk(['dc.snapshot_date']) }}                            as mart_customer_sk,

    dc.snapshot_date,
    dd.date_sk,
    dd.month_number,
    dd.month_name,
    dd.quarter_number,
    dd.quarter_name,
    dd.year,
    dd.is_mtd,
    dd.is_qtd,
    dd.is_ytd,

    -- KPI 10 (NON-ADDITIVE — point-in-time count)
    dc.active_customers_30d,
    -- KPI 11 (NON-ADDITIVE — point-in-time count)
    dc.active_customers_90d,
    -- Supplementary
    dc.total_tracked_customers,
    dc.new_in_30d_window,
    dc.repeat_customers,
    dc.avg_lifetime_revenue,
    dc.avg_lifetime_orders,
    dc.total_trailing_30d_revenue,
    dc.total_trailing_90d_revenue,

    current_timestamp()                                                    as loaded_at,

    {{ add_audit_columns(
        source_system='generated',
        source_id_column='dc.snapshot_date',
        business_columns=['dc.snapshot_date'],
        extracted_at_column='current_timestamp()'
    ) }}

from daily_counts dc
left join {{ ref('dim_date') }} dd
    on dd.date_sk = year(dc.snapshot_date) * 10000
                  + month(dc.snapshot_date) * 100
                  + day(dc.snapshot_date)
