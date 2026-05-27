{{ config(materialized='table') }}

-- Pro Email Engagement mart per Phase 2. KPI 19 §5.5 — Email Engagement Rate.
-- Grain: one row per (event_date × email_campaign_sk).
-- KPI 19: (total_opened + total_clicked) / NULLIF(total_delivered, 0) * 100 in Power BI.
-- Stored components also support open_rate and click_rate variants.
-- Apple Mail Privacy Protection inflates total_opened counts — documented, not adjusted.
-- Slicers: Email Campaign, Customer Segment, Geography (segment/geo require customer join in Power BI).

with events as (
    select
        fee.event_date,
        fee.email_campaign_sk,
        fee.customer_sk,
        fee.event_type
    from {{ ref('fact_email_engagement') }} fee
),

daily_campaign as (
    select
        event_date,
        email_campaign_sk,
        count(case when event_type = 'delivered'     then 1 end) as total_delivered,
        count(case when event_type = 'opened'        then 1 end) as total_opened,
        count(case when event_type = 'clicked'       then 1 end) as total_clicked,
        count(case when event_type = 'bounced'       then 1 end) as total_bounced,
        count(case when event_type = 'unsubscribed'  then 1 end) as total_unsubscribed,
        count(case when event_type = 'spam_reported' then 1 end) as total_spam_reported,
        count(distinct customer_sk)                               as unique_recipients
    from events
    group by event_date, email_campaign_sk
)

select
    {{ generate_dim_sk(['dc.event_date', 'dc.email_campaign_sk']) }}        as mart_pro_email_sk,

    dc.event_date,
    dd.date_sk,
    dd.week_of_year,
    dd.month_number,
    dd.month_name,
    dd.quarter_number,
    dd.year,
    dd.is_mtd,
    dd.is_qtd,
    dd.is_ytd,

    dc.email_campaign_sk,
    dec.email_campaign_id,
    dec.campaign_name,
    dec.campaign_type,
    dec.subject_line,
    dec.send_date,
    dec.audience_size,

    -- KPI 19 basis: (total_opened + total_clicked) / NULLIF(total_delivered, 0) * 100 in Power BI
    dc.total_delivered,
    dc.total_opened,
    dc.total_clicked,
    dc.total_bounced,
    dc.total_unsubscribed,
    dc.total_spam_reported,
    dc.unique_recipients,

    current_timestamp()                                                     as loaded_at,

    {{ add_audit_columns(
        source_system='klaviyo',
        source_id_column="cast(dc.event_date as varchar) || '|' || coalesce(cast(dc.email_campaign_sk as varchar), 'null')",
        business_columns=['dc.event_date', 'dc.email_campaign_sk'],
        extracted_at_column='current_timestamp()'
    ) }}

from daily_campaign dc
left join {{ ref('dim_date') }} dd
    on dd.date_sk = year(dc.event_date) * 10000
                  + month(dc.event_date) * 100
                  + day(dc.event_date)
left join {{ ref('dim_email_campaign') }} dec
    on dec.email_campaign_sk = dc.email_campaign_sk
