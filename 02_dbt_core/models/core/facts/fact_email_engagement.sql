{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='event_id',
    on_schema_change='append_new_columns',
    cluster_by=['event_date', 'customer_sk', 'email_campaign_sk']
) }}

-- fact_email_engagement per §4.24. One row per Klaviyo engagement event.
-- Source: stg_klaviyo__events (event_type already mapped from Klaviyo raw event names).
-- customer_sk: klaviyo_profile_id → dim_customer (current version).
-- email_campaign_sk: COALESCE('cmp_' + campaign_id, 'flw_' + flow_id) → dim_email_campaign.
-- link_url, email_subject, bounce details extracted from event_properties VARIANT.
-- Lookback: 3 days — Klaviyo events settle quickly; occasional delayed deliveries handled.

with events as (
    select * from {{ ref('stg_klaviyo__events') }}
    {{ incremental_lookback('event_timestamp', 'fact_email_engagement') }}
),

-- Derive the prefixed email_campaign_id matching dim_email_campaign's IDs
events_enriched as (
    select
        *,
        case
            when campaign_id is not null and campaign_id != ''
                then 'cmp_' || campaign_id
            when flow_id     is not null and flow_id     != ''
                then 'flw_' || flow_id
        end                                                             as email_campaign_id
    from events
)

select
    {{ generate_dim_sk(['e.event_id']) }}                               as event_sk,
    e.event_id,

    -- Customer FK: match by Klaviyo profile ID (current dim version)
    dc.customer_sk,

    -- Email campaign FK
    dec.email_campaign_sk,

    e.event_type,
    e.event_date,
    e.event_timestamp,

    -- Email metadata from event_properties VARIANT
    try_cast(e.event_properties:subject_line::varchar as varchar)       as email_subject,
    try_cast(e.event_properties:url::varchar          as varchar)       as link_url,

    -- Bounce details (present only for bounced events)
    case lower(try_cast(e.event_properties:bounce_type::varchar as varchar))
        when 'hard'  then 'hard'
        when 'soft'  then 'soft'
        when 'block' then 'block'
        else try_cast(e.event_properties:bounce_type::varchar as varchar)
    end                                                                 as bounce_type,
    try_cast(e.event_properties:error_message::varchar as varchar)      as bounce_reason,

    -- Device from Klaviyo $device_type property
    try_cast(e.event_properties['$device_type']::varchar as varchar)   as device_type,

    current_timestamp()                                                 as loaded_at,

    {{ add_audit_columns(
        source_system='klaviyo',
        source_id_column='e.event_id',
        business_columns=['e.event_id', 'e.event_timestamp'],
        extracted_at_column='e._extracted_at'
    ) }}

from events_enriched e
-- Customer: match by klaviyo_profile_id (current SCD2 version)
left join {{ ref('dim_customer') }} dc
    on dc.klaviyo_profile_id = e.klaviyo_profile_id
    and dc.is_current = true
-- Email campaign
left join {{ ref('dim_email_campaign') }} dec
    on dec.email_campaign_id = e.email_campaign_id
