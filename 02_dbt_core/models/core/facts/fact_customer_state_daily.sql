{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['customer_id', 'snapshot_date'],
    on_schema_change='append_new_columns',
    cluster_by=['snapshot_date', 'customer_sk']
) }}

-- fact_customer_state_daily per §4.25. One row per active customer per day.
-- Pattern: daily dbt job generates rows for current_date() only.
--   Incremental: MERGE upserts today's row (idempotent re-runs safe).
--   Full refresh: still generates today's row only; historical backfill via orchestrator.
-- Active customer definition: any customer updated in last 24 months OR marketing_consent=TRUE.
-- OSS columns: 1-18 (state tracking, activity flags, repeat/new flags).
-- Pro columns 19-25 (RFM tiers, churn probability, predicted LTV) — NULL in OSS per §11.

with snapshot_date_cte as (
    -- Always generates today's snapshot; historical backfill = re-run with date override
    select current_date() as snapshot_date
),

active_customers as (
    select
        customer_sk,
        customer_id,
        acquisition_date,
        is_current
    from {{ ref('dim_customer') }}
    where is_current = true
      and (
          updated_at >= dateadd('month', -24, current_date())
          or marketing_consent = true
      )
),

-- Lifetime and trailing order metrics, computed as of snapshot_date
order_metrics as (
    select
        fo.customer_id,
        sd.snapshot_date,

        -- Lifetime
        min(fo.order_date)                                              as first_order_date,
        max(fo.order_date)                                              as last_order_date,
        count(*)                                                        as lifetime_order_count,
        sum(fo.net_after_refunds)                                       as lifetime_revenue,
        sum(fo.total_quantity)                                          as lifetime_quantity,

        -- Trailing 30 days
        count(case when fo.order_date >= dateadd('day', -29, sd.snapshot_date)
                   then 1 end)                                          as trailing_30d_order_count,
        sum(case when fo.order_date >= dateadd('day', -29, sd.snapshot_date)
                 then fo.net_after_refunds else 0 end)                 as trailing_30d_revenue,

        -- Trailing 90 days
        count(case when fo.order_date >= dateadd('day', -89, sd.snapshot_date)
                   then 1 end)                                          as trailing_90d_order_count,
        sum(case when fo.order_date >= dateadd('day', -89, sd.snapshot_date)
                 then fo.net_after_refunds else 0 end)                 as trailing_90d_revenue

    from {{ ref('fact_orders') }} fo
    cross join snapshot_date_cte sd
    where fo.order_status not in ('cancelled')
      and fo.order_date <= sd.snapshot_date
      and fo.customer_id is not null
    group by fo.customer_id, sd.snapshot_date
)

select
    {{ generate_dim_sk(['ac.customer_id', 'sd.snapshot_date']) }}       as customer_state_sk,
    ac.customer_sk,
    ac.customer_id,
    sd.snapshot_date,

    -- Days since acquisition (first seen in any source system)
    datediff('day', ac.acquisition_date::date, sd.snapshot_date)       as days_since_acquisition,

    -- Days since first and last order (NULL for never-ordered customers)
    case when om.first_order_date is not null
         then datediff('day', om.first_order_date, sd.snapshot_date)
    end                                                                 as days_since_first_order,
    case when om.last_order_date is not null
         then datediff('day', om.last_order_date, sd.snapshot_date)
    end                                                                 as days_since_last_order,

    -- Lifetime metrics
    coalesce(om.lifetime_order_count, 0)                                as lifetime_order_count,
    coalesce(om.lifetime_revenue,     0.0)                              as lifetime_revenue,
    coalesce(om.lifetime_quantity,    0.0)                              as lifetime_quantity,

    -- Trailing window metrics
    coalesce(om.trailing_30d_order_count, 0)                            as trailing_30d_order_count,
    coalesce(om.trailing_30d_revenue,     0.0)                          as trailing_30d_revenue,
    coalesce(om.trailing_90d_order_count, 0)                            as trailing_90d_order_count,
    coalesce(om.trailing_90d_revenue,     0.0)                          as trailing_90d_revenue,

    -- Activity flags
    coalesce(om.trailing_30d_order_count, 0) > 0                        as is_active_30d,
    coalesce(om.trailing_90d_order_count, 0) > 0                        as is_active_90d,
    datediff('day', ac.acquisition_date::date, sd.snapshot_date) <= 30  as is_new_30d,
    coalesce(om.lifetime_order_count, 0) >= 2                           as is_repeat_customer,

    -- Pro columns — NULL in OSS per §11 (RFM, churn prediction, LTV)
    cast(null as varchar)                                               as customer_segment,
    cast(null as varchar)                                               as rfm_recency_tier,
    cast(null as varchar)                                               as rfm_frequency_tier,
    cast(null as varchar)                                               as rfm_monetary_tier,
    cast(null as numeric(5,4))                                          as predicted_churn_probability,
    cast(null as numeric(18,4))                                         as predicted_ltv,

    current_timestamp()                                                 as loaded_at,

    {{ add_audit_columns(
        source_system='generated',
        source_id_column="ac.customer_id || '_' || cast(sd.snapshot_date as varchar)",
        business_columns=['ac.customer_id', 'sd.snapshot_date'],
        extracted_at_column='current_timestamp()'
    ) }}

from active_customers ac
cross join snapshot_date_cte sd
left join order_metrics om
    on om.customer_id  = ac.customer_id
    and om.snapshot_date = sd.snapshot_date
