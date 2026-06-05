{{ config(materialized='view') }}

-- Klaviyo engagement events (opens, clicks, bounces, conversions).
-- Event names are mapped to canonical event_type values per §6.8.
-- event_properties kept as VARIANT for downstream extraction in intermediate/mart layers.
--
-- Note: Klaviyo event volume is high (millions/month for active accounts).
-- The 30-day incremental lookback on fact_email_engagement handles profile re-merges (§6.8).

with source as (
    select * from {{ source('klaviyo', 'events') }}
),

renamed as (
    select
        cast(id         as varchar)                                              as event_id,
        cast(profile_id as varchar)                                             as klaviyo_profile_id,

        -- canonical event type mapping per §6.8
        case
            when cast(event_name as varchar) = 'Received Email'           then 'delivered'
            when cast(event_name as varchar) = 'Opened Email'             then 'opened'
            when cast(event_name as varchar) = 'Clicked Email'            then 'clicked'
            when cast(event_name as varchar) = 'Bounced Email'            then 'bounced'
            when cast(event_name as varchar) = 'Unsubscribed'             then 'unsubscribed'
            when cast(event_name as varchar) = 'Marked Email as Spam'     then 'marked_spam'
            when cast(event_name as varchar) = 'Placed Order'             then 'converted'
            else 'other'
        end                                                                     as event_type,
        cast(event_name as varchar)                                             as event_name_raw,

        -- campaign or flow that triggered this event
        cast({{ source_col('klaviyo', 'events', 'campaign_id', 'campaign_id') }} as varchar) as campaign_id,
        cast({{ source_col('klaviyo', 'events', 'flow_id',     'flow_id')     }} as varchar) as flow_id,

        cast(datetime as timestamp_tz)                                          as event_timestamp,
        cast(datetime as date)                                                  as event_date,

        -- event_properties kept as VARIANT; link_url and subject extracted in mart layer
        try_parse_json(cast(event_properties as varchar))                      as event_properties,

        datetime                                                                as _extracted_at
    from source
)

select
    event_id,
    klaviyo_profile_id,
    event_type,
    event_name_raw,
    campaign_id,
    flow_id,
    event_timestamp,
    event_date,
    event_properties,
    {{ add_audit_columns(
        source_system='klaviyo',
        source_id_column='event_id',
        business_columns=['event_id', 'event_timestamp'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
