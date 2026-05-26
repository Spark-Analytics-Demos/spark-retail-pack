{{ config(materialized='table') }}

-- Email campaign and flow dimension from Klaviyo per §4.11.
-- UNION of one-time campaigns (stg_klaviyo__campaigns) and automated flows
-- (stg_klaviyo__flows). Type 1 — history not tracked.
-- email_campaign_id is prefixed to avoid collisions: 'cmp_' for campaigns, 'flw_' for flows.

with campaigns as (
    select
        'cmp_' || campaign_id                                  as email_campaign_id,
        campaign_name,
        campaign_type,
        cast(null as varchar)                                  as flow_step,
        subject_line,
        send_date,
        cast(null as varchar)                                  as target_segment,
        audience_size,
        -- active = campaign is scheduled/draft (not yet sent)
        (not is_sent)                                          as is_active,
        created_at,
        updated_at,
        _extracted_at
    from {{ ref('stg_klaviyo__campaigns') }}
),

flows as (
    select
        'flw_' || flow_id                                      as email_campaign_id,
        flow_name                                              as campaign_name,
        campaign_type,
        cast(null as varchar)                                  as flow_step,
        cast(null as varchar)                                  as subject_line,
        send_date,
        cast(null as varchar)                                  as target_segment,
        cast(null as int)                                      as audience_size,
        is_active,
        created_at,
        updated_at,
        _extracted_at
    from {{ ref('stg_klaviyo__flows') }}
),

unioned as (
    select * from campaigns
    union all
    select * from flows
)

select
    {{ generate_dim_sk(['email_campaign_id']) }}  as email_campaign_sk,
    email_campaign_id,
    campaign_name,
    campaign_type,
    flow_step,
    subject_line,
    send_date,
    target_segment,
    audience_size,
    is_active,
    created_at,
    updated_at,
    {{ add_audit_columns(
        source_system='klaviyo',
        source_id_column='email_campaign_id',
        business_columns=['email_campaign_id', 'campaign_type'],
        extracted_at_column='_extracted_at'
    ) }}
from unioned
