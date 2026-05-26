{{ config(
    materialized='incremental',
    incremental_strategy='append',
    unique_key='session_id',
    on_schema_change='append_new_columns',
    cluster_by=['session_date', 'customer_sk', 'channel_sk']
) }}

-- fact_web_sessions per §4.23. One row per GA4 session.
-- Source: int_ga4_session_aggregation (event-grain → session-grain).
-- channel_sk: traffic_source + traffic_medium → channel_mapping seed → dim_channel.
-- customer_sk: GA4 user_id → dim_customer.customer_id (NULL for anonymous sessions).
--   Note: cross-device session stitching is a Pro feature (§11); basic login-ID match only here.
-- geography_sk: geo_country → dim_geography (country-level only).
-- Lookback: 3 days — GA4 sessions settle quickly; backfills are rare.

with sessions as (
    select * from {{ ref('int_ga4_session_aggregation') }}
    {{ incremental_lookback('session_date', 'fact_web_sessions') }}
),

-- traffic_source + traffic_medium → channel_id
-- GA4 sends '(direct)' for direct sessions and '(none)' for no medium
channel_map as (
    select source_value, channel_id
    from {{ ref('channel_mapping') }}
    where source_system = 'ga4'
),

-- Canonical channel key: 'source / medium' concatenation matches channel_mapping seed convention
sessions_channel as (
    select
        s.*,
        lower(
            coalesce(s.traffic_source, '(direct)')
            || ' / '
            || coalesce(s.traffic_medium, '(none)')
        )                                                               as traffic_key
    from sessions s
)

select
    {{ generate_dim_sk(['s.session_id']) }}                             as session_sk,
    s.session_id,
    s.user_pseudo_id,

    -- Customer FK: basic user_id → customer_id match (logged-in sessions only)
    dc.customer_sk,
    dc.customer_id,

    -- Channel FK
    dch.channel_sk,

    -- Geography FK
    dg.geography_sk,

    s.session_date,
    s.session_start_timestamp,
    s.session_duration_seconds,
    s.page_views,
    s.events_count,
    s.device_category,
    cast(null as varchar)                                               as device_brand,
    s.device_os,
    s.browser,
    s.traffic_source,
    s.traffic_medium,
    s.traffic_campaign,
    cast(null as varchar)                                               as traffic_content,
    cast(null as varchar)                                               as traffic_term,
    s.landing_page,
    s.exit_page,
    s.has_purchase_event,
    cast(s.transaction_revenue as numeric(18,4))                        as transaction_revenue,
    s.is_new_user,

    current_timestamp()                                                 as loaded_at,

    {{ add_audit_columns(
        source_system='ga4',
        source_id_column='s.session_id',
        business_columns=['s.session_id'],
        extracted_at_column='s.session_start_timestamp'
    ) }}

from sessions_channel s
-- Customer: logged-in sessions where GA4 user_id matches canonical customer_id
left join {{ ref('dim_customer') }} dc
    on dc.customer_id = s.user_id
    and dc.is_current = true
    and s.user_id is not null
-- Channel: exact source/medium key, fall back to wildcard
left join channel_map cm_exact
    on cm_exact.source_value = s.traffic_key
left join channel_map cm_wild
    on cm_wild.source_value = '*'
left join {{ ref('dim_channel') }} dch
    on dch.channel_id = coalesce(cm_exact.channel_id, cm_wild.channel_id)
-- Geography: country-level rows only
left join {{ ref('dim_geography') }} dg
    on dg.country_code = s.geo_country
    and dg.state_or_region_code is null
