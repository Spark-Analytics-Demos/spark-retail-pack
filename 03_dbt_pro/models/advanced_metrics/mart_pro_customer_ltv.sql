{{ config(materialized='table') }}

-- Pro Customer LTV mart per Phase 2. KPI 15 §5.5 — Customer Lifetime Value (basic).
-- Grain: one row per (snapshot_date × acquisition_cohort_month × acquisition_source_system).
-- KPI 15: avg_ltv = AVG(lifetime_revenue) as-of snapshot_date. NON-ADDITIVE across time.
-- Slicers: Acquisition Cohort (month), acquisition_source_system (proxy for channel in v1).
-- acquisition_channel: uses acquisition_source_system as proxy; Pro channel enrichment in v2.
-- Percentile distribution (p25/p50/p75) supports cohort LTV dispersion analysis.

with customer_state as (
    select
        fcs.snapshot_date,
        fcs.customer_id,
        fcs.lifetime_revenue,
        fcs.lifetime_order_count,
        fcs.is_active_30d,
        fcs.is_active_90d
    from {{ ref('fact_customer_state_daily') }} fcs
),

customer_attrs as (
    select
        customer_id,
        acquisition_source_system,
        date_trunc('month', acquisition_date::date)::date   as acquisition_cohort_month
    from {{ ref('dim_customer') }}
    where is_current = true
),

cohort_daily as (
    select
        cs.snapshot_date,
        ca.acquisition_cohort_month,
        ca.acquisition_source_system,
        count(distinct cs.customer_id)                                      as total_customers_in_cohort,
        avg(cs.lifetime_revenue)                                             as avg_ltv,
        percentile_cont(0.25) within group (order by cs.lifetime_revenue)   as p25_ltv,
        percentile_cont(0.50) within group (order by cs.lifetime_revenue)   as p50_ltv,
        percentile_cont(0.75) within group (order by cs.lifetime_revenue)   as p75_ltv,
        sum(cs.lifetime_revenue)                                             as total_cohort_lifetime_revenue,
        avg(cs.lifetime_order_count)                                         as avg_lifetime_orders,
        count(distinct case when cs.is_active_30d then cs.customer_id end)  as active_customers_30d,
        count(distinct case when cs.is_active_90d then cs.customer_id end)  as active_customers_90d
    from customer_state cs
    inner join customer_attrs ca
        on ca.customer_id = cs.customer_id
    group by
        cs.snapshot_date,
        ca.acquisition_cohort_month,
        ca.acquisition_source_system
)

select
    {{ generate_dim_sk(['cd.snapshot_date', 'cd.acquisition_cohort_month', 'cd.acquisition_source_system']) }}
                                                                            as mart_pro_ltv_sk,

    cd.snapshot_date,
    dd.date_sk,
    dd.month_number,
    dd.month_name,
    dd.quarter_number,
    dd.year,
    dd.is_mtd,
    dd.is_ytd,

    cd.acquisition_cohort_month,
    cd.acquisition_source_system,

    -- KPI 15 (NON-ADDITIVE — point-in-time per cohort/snapshot_date)
    cd.avg_ltv,
    cd.p25_ltv,
    cd.p50_ltv,
    cd.p75_ltv,
    cd.total_cohort_lifetime_revenue,
    cd.avg_lifetime_orders,
    cd.total_customers_in_cohort,
    -- Active sub-counts within this cohort on this snapshot_date
    cd.active_customers_30d,
    cd.active_customers_90d,

    current_timestamp()                                                     as loaded_at,

    {{ add_audit_columns(
        source_system='generated',
        source_id_column="cast(cd.snapshot_date as varchar) || '|' || coalesce(cast(cd.acquisition_cohort_month as varchar), 'null') || '|' || coalesce(cd.acquisition_source_system, 'null')",
        business_columns=['cd.snapshot_date', 'cd.acquisition_cohort_month'],
        extracted_at_column='current_timestamp()'
    ) }}

from cohort_daily cd
left join {{ ref('dim_date') }} dd
    on dd.date_sk = year(cd.snapshot_date) * 10000
                  + month(cd.snapshot_date) * 100
                  + day(cd.snapshot_date)
