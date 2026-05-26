{{ config(materialized='table') }}

-- Paid marketing campaign dimension from snap_marketing_campaign (SCD2) per §4.10.
-- Source is Meta Ads campaigns in v1. Future: Google Ads, TikTok Ads (Pro connectors).
-- channel_sk is resolved via FK join to dim_channel for the canonical Meta channel.
--
-- Stubbed NULL columns (require data not in Meta Ads campaign API):
--   bid_strategy, target_audience — set at ad-set level, not campaign level
--   utm_source, utm_medium, utm_campaign — client-managed URL parameters

with snapshot as (
    select
        campaign_id,
        meta_campaign_id,
        account_id,
        campaign_name,
        campaign_objective,
        campaign_status,
        buying_type,
        daily_budget,
        lifetime_budget,
        start_at,
        end_at,
        start_date,
        end_date,
        is_active,
        created_at,
        updated_at,
        dbt_valid_from,
        dbt_valid_to,
        _extracted_at
    from {{ ref('snap_marketing_campaign') }}
),

channel_lookup as (
    select channel_sk, channel_id
    from {{ ref('dim_channel') }}
)

select
    {{ generate_dim_sk(['campaign_id'], 'dbt_valid_from') }}  as campaign_sk,
    campaign_id,

    -- platform prefix distinguishes source; 'meta_' prefix set in staging
    'meta'                                                     as platform,

    campaign_name,

    -- map Meta objective codes to canonical pack vocabulary
    case upper(campaign_objective)
        when 'OUTCOME_SALES'        then 'conversions'
        when 'OUTCOME_TRAFFIC'      then 'traffic'
        when 'OUTCOME_AWARENESS'    then 'awareness'
        when 'OUTCOME_ENGAGEMENT'   then 'engagement'
        when 'OUTCOME_LEADS'        then 'leads'
        when 'OUTCOME_APP_PROMOTION' then 'app_installs'
        else lower(campaign_objective)
    end                                                        as campaign_objective,

    -- map Meta status codes to canonical lowercase values
    lower(campaign_status)                                     as campaign_status,

    lower(buying_type)                                         as buying_type,
    start_date,
    end_date,
    daily_budget,
    lifetime_budget,

    -- stubbed: requires ad-set level data not captured in v1 Meta connector
    cast(null as varchar)                                      as bid_strategy,
    cast(null as varchar)                                      as target_audience,

    -- FK to dim_channel — all Meta campaigns map to paid_social_meta
    dc.channel_sk,

    -- stubbed: client-managed UTM parameters not in Meta campaign API
    cast(null as varchar)                                      as utm_source,
    cast(null as varchar)                                      as utm_medium,
    cast(null as varchar)                                      as utm_campaign,

    created_at,

    -- SCD2 columns
    dbt_valid_from                                             as valid_from,
    dbt_valid_to                                               as valid_to,
    (dbt_valid_to is null)                                     as is_current,

    {{ add_audit_columns(
        source_system='meta_ads',
        source_id_column='campaign_id',
        business_columns=['campaign_id', 'campaign_status'],
        extracted_at_column='_extracted_at'
    ) }}
from snapshot s
left join channel_lookup dc
    on dc.channel_id = 'paid_social_meta'
