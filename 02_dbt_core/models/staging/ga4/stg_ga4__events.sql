{{ config(materialized='view') }}

-- GA4 staging model — Path 1 (BigQuery export via Fivetran/Airbyte BigQuery connector).
-- One row per event per session. Aggregated to session-grain in int_ga4_session_aggregation.
--
-- Connector note: Fivetran's BigQuery connector flattens GA4 nested structs using double-
-- underscore notation (e.g. device.category → device__category, traffic_source.source →
-- traffic_source__source). event_timestamp is INT64 microseconds since epoch in BigQuery;
-- staging converts to TIMESTAMP_TZ via division by 1,000,000.
-- For Path 2 (GA4 Reporting API connector), timestamps are already converted and device/
-- traffic fields may use different column names — override via source_mapping_overrides.

with source as (
    select * from {{ source('ga4', 'events') }}
),

renamed as (
    select
        -- session composite key: user_pseudo_id + ga_session_id (§6.6)
        cast(user_pseudo_id as varchar)                                          as user_pseudo_id,
        cast(user_id        as varchar)                                          as user_id,

        cast({{ source_col('ga4', 'events', 'ga_session_id', 'ga_session_id') }} as varchar) as ga_session_id,

        -- event identity
        cast(event_name as varchar)                                              as event_name,
        -- event_date is GA4's 'YYYYMMDD' string. The format mask is REQUIRED:
        -- to_date('20261010') with no mask parses an all-digit string as epoch
        -- SECONDS (→ 1970-08-23), not a calendar date. See ADR-005 follow-up.
        to_date(cast(event_date as varchar), 'YYYYMMDD')                         as event_date,

        -- event_timestamp: INT64 microseconds since epoch → TIMESTAMP_TZ
        to_timestamp_tz(
            cast({{ source_col('ga4', 'events', 'event_timestamp', 'event_timestamp') }} as number) / 1000000
        )                                                                        as event_timestamp,

        -- device: Fivetran flattens device struct with double-underscore separator
        cast({{ source_col('ga4', 'events', 'device_category',      'device__category')            }} as varchar) as device_category,
        cast({{ source_col('ga4', 'events', 'device_mobile_brand',  'device__mobile_brand_name')   }} as varchar) as device_mobile_brand,
        cast({{ source_col('ga4', 'events', 'device_os',            'device__operating_system')    }} as varchar) as device_os,
        cast({{ source_col('ga4', 'events', 'browser',              'device__web_info__browser')   }} as varchar) as browser,

        -- traffic source: Fivetran flattens traffic_source struct
        cast({{ source_col('ga4', 'events', 'traffic_source',   'traffic_source__source') }} as varchar) as traffic_source,
        cast({{ source_col('ga4', 'events', 'traffic_medium',   'traffic_source__medium') }} as varchar) as traffic_medium,
        cast({{ source_col('ga4', 'events', 'traffic_campaign', 'traffic_source__name')   }} as varchar) as traffic_campaign,

        -- geography: Fivetran flattens geo struct
        cast({{ source_col('ga4', 'events', 'geo_country',  'geo__country')  }} as varchar) as geo_country,
        cast({{ source_col('ga4', 'events', 'geo_region',   'geo__region')   }} as varchar) as geo_region,

        -- page (populated on page_view events)
        cast({{ source_col('ga4', 'events', 'page_location', 'page_location') }} as varchar) as page_location,
        cast({{ source_col('ga4', 'events', 'page_referrer', 'page_referrer') }} as varchar) as page_referrer,
        cast({{ source_col('ga4', 'events', 'page_title',    'page_title')    }} as varchar) as page_title,

        -- ecommerce (populated on purchase events)
        cast({{ source_col('ga4', 'events', 'transaction_id',      'ecommerce__transaction_id')       }} as varchar)        as transaction_id,
        cast({{ source_col('ga4', 'events', 'purchase_value',      'ecommerce__purchase_revenue')     }} as numeric(18, 6)) as purchase_value,
        upper(cast({{ source_col('ga4', 'events', 'purchase_currency', 'ecommerce__currency') }} as varchar)) as purchase_currency,

        -- engagement score (populated on session_start / user_engagement events)
        cast({{ source_col('ga4', 'events', 'engagement_time_msec', 'engagement_time_msec') }} as int) as engagement_time_msec,

        -- new vs returning user flag
        cast({{ source_col('ga4', 'events', 'is_new_user', 'is_new_user') }} as boolean) as is_new_user
    from source
)

select
    user_pseudo_id,
    user_id,
    ga_session_id,
    event_name,
    event_date,
    event_timestamp,
    device_category,
    device_mobile_brand,
    device_os,
    browser,
    traffic_source,
    traffic_medium,
    traffic_campaign,
    geo_country,
    geo_region,
    page_location,
    page_referrer,
    page_title,
    transaction_id,
    purchase_value,
    purchase_currency,
    engagement_time_msec,
    is_new_user,
    {{ add_audit_columns(
        source_system='ga4',
        source_id_column="user_pseudo_id || '_' || coalesce(ga_session_id, 'unknown') || '_' || event_name || '_' || cast(event_timestamp as varchar)",
        business_columns=['user_pseudo_id', 'ga_session_id', 'event_timestamp'],
        extracted_at_column='current_timestamp()'
    ) }}
from renamed
