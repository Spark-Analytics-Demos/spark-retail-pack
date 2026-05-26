{{ config(materialized='ephemeral') }}

-- GA4 event-grain → session-grain aggregation per §6.6 (int_ga4_session_aggregation spec).
-- Output: one row per user_pseudo_id + ga_session_id.
-- Sessions with events_count = 1 AND session_duration_seconds = 0 are flagged as
-- potential bots (is_bot_session = true) but retained — removal is a downstream concern.
-- Landing/exit pages computed via ranked page_view events to avoid window + GROUP BY mixing.

with events as (
    select
        user_pseudo_id,
        user_id,
        ga_session_id,
        event_name,
        event_date,
        event_timestamp,
        device_category,
        device_os,
        browser,
        traffic_source,
        traffic_medium,
        traffic_campaign,
        geo_country,
        geo_region,
        page_location,
        transaction_id,
        purchase_value,
        purchase_currency,
        engagement_time_msec,
        is_new_user
    from {{ ref('stg_ga4__events') }}
    where ga_session_id is not null
),

session_agg as (
    select
        user_pseudo_id,
        ga_session_id,
        user_pseudo_id || '_' || ga_session_id   as session_id,

        -- Logged-in user (null for anonymous sessions)
        max(user_id)                              as user_id,

        -- Session timing
        min(event_date)                           as session_date,
        min(event_timestamp)                      as session_start_timestamp,
        max(event_timestamp)                      as session_end_timestamp,
        datediff('second',
            min(event_timestamp),
            max(event_timestamp)
        )                                         as session_duration_seconds,

        -- Engagement (sum of all engagement_time_msec events, converted to seconds)
        sum(coalesce(engagement_time_msec, 0)) / 1000.0 as engagement_time_seconds,

        -- Event counts
        count(*)                                                            as events_count,
        count(case when event_name = 'page_view' then 1 end)               as page_views,

        -- Device and browser (constant within a GA4 session)
        any_value(device_category)                as device_category,
        any_value(device_os)                      as device_os,
        any_value(browser)                        as browser,

        -- Traffic source (set at session start by GA4)
        any_value(traffic_source)                 as traffic_source,
        any_value(traffic_medium)                 as traffic_medium,
        any_value(traffic_campaign)               as traffic_campaign,

        -- Geography
        any_value(geo_country)                    as geo_country,
        any_value(geo_region)                     as geo_region,

        -- Purchase / ecommerce
        boolor_agg(event_name = 'purchase')       as has_purchase_event,
        max(case when event_name = 'purchase'
                 then transaction_id   end)       as transaction_id,
        sum(case when event_name = 'purchase'
                 then coalesce(purchase_value, 0) else 0 end) as transaction_revenue,
        max(case when event_name = 'purchase'
                 then purchase_currency end)      as purchase_currency,

        -- New user flag (true if any event in session carries is_new_user = true)
        boolor_agg(coalesce(is_new_user, false))  as is_new_user
    from events
    group by user_pseudo_id, ga_session_id
),

-- Landing page: first page_view event per session
page_view_events as (
    select
        user_pseudo_id,
        ga_session_id,
        page_location,
        event_timestamp,
        row_number() over (
            partition by user_pseudo_id, ga_session_id
            order by event_timestamp asc
        ) as rn_asc,
        row_number() over (
            partition by user_pseudo_id, ga_session_id
            order by event_timestamp desc
        ) as rn_desc
    from events
    where event_name = 'page_view'
      and page_location is not null
),

landing_pages as (
    select user_pseudo_id, ga_session_id, page_location as landing_page
    from page_view_events
    where rn_asc = 1
),

exit_pages as (
    select user_pseudo_id, ga_session_id, page_location as exit_page
    from page_view_events
    where rn_desc = 1
)

select
    s.session_id,
    s.user_pseudo_id,
    s.ga_session_id,
    s.user_id,
    s.session_date,
    s.session_start_timestamp,
    s.session_end_timestamp,
    s.session_duration_seconds,
    s.engagement_time_seconds,
    s.events_count,
    s.page_views,
    s.device_category,
    s.device_os,
    s.browser,
    s.traffic_source,
    s.traffic_medium,
    s.traffic_campaign,
    s.geo_country,
    s.geo_region,
    lp.landing_page,
    ep.exit_page,
    s.has_purchase_event,
    s.transaction_id,
    s.transaction_revenue,
    s.purchase_currency,
    s.is_new_user,
    -- Bot session flag: single event with zero duration (§6.6 edge cases)
    (s.events_count = 1 and s.session_duration_seconds = 0) as is_bot_session
from session_agg s
left join landing_pages lp
    on s.user_pseudo_id = lp.user_pseudo_id
    and s.ga_session_id  = lp.ga_session_id
left join exit_pages ep
    on s.user_pseudo_id = ep.user_pseudo_id
    and s.ga_session_id  = ep.ga_session_id
