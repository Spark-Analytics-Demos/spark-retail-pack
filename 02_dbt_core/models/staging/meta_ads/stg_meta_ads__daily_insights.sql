{{ config(materialized='table') }}

-- Meta Ads daily performance metrics. One row per day per ad (or ad_set/campaign if
-- connector is configured at a higher granularity).
--
-- Connector note: Meta's 'actions' field is a repeated JSON array.
-- Fivetran typically creates a separate 'actions' table rather than keeping actions as
-- VARIANT on this table. If your connector provides actions as a VARIANT column, set
-- source_mapping_overrides.meta_ads__daily_insights.field_mappings.actions_raw to the
-- column name and the LATERAL FLATTEN below will work as-is.
-- If actions are in a separate table, override this model in your deployment with a JOIN.
--
-- Platform-reported conversions are stored for reference only.
-- Attribution uses UTM-matched warehouse data, not Meta's reported figures (§6.7).

with source as (
    select * from {{ source('meta_ads', 'daily_insights') }}
),

-- Snowflake does not support LATERAL FLATTEN inside a scalar subquery.
-- Aggregate purchase conversions per row in separate CTEs, then join back.
actions_agg as (
    select
        date_start,
        campaign_id,
        ad_set_id,
        ad_id,
        coalesce(
            sum(case
                when a.value:action_type::varchar = 'purchase'
                then try_cast(a.value:value::varchar as numeric(18, 6))
            end),
            0
        )::numeric(18, 6)                                                        as platform_reported_conversions
    from source,
        lateral flatten(
            input  => try_parse_json(cast({{ source_col('meta_ads', 'daily_insights', 'actions_raw', 'actions') }} as varchar)),
            outer  => true
        ) a
    group by 1, 2, 3, 4
),

action_values_agg as (
    select
        date_start,
        campaign_id,
        ad_set_id,
        ad_id,
        coalesce(
            sum(case
                when av.value:action_type::varchar = 'purchase'
                then try_cast(av.value:value::varchar as numeric(18, 6))
            end),
            0
        )::numeric(18, 6)                                                        as platform_reported_conversion_value
    from source,
        lateral flatten(
            input  => try_parse_json(cast({{ source_col('meta_ads', 'daily_insights', 'action_values_raw', 'action_values') }} as varchar)),
            outer  => true
        ) av
    group by 1, 2, 3, 4
),

renamed as (
    select
        cast(s.date_start  as date)                                              as spend_date,
        'meta_' || cast(s.campaign_id as varchar)                                as campaign_id,
        cast(s.campaign_id as varchar)                                           as meta_campaign_id,
        cast(s.ad_set_id   as varchar)                                           as ad_set_id,
        cast(s.ad_id       as varchar)                                           as ad_id,

        cast(s.spend as numeric(18, 6))                                          as spend_amount_local,

        cast(s.impressions as int)                                               as impressions,
        cast(s.clicks      as int)                                               as clicks,
        cast(coalesce(s.reach, 0) as int)                                        as reach,
        cast(coalesce(s.inline_link_clicks, 0) as int)                           as link_clicks,

        coalesce(aa.platform_reported_conversions, 0)                            as platform_reported_conversions,
        coalesce(ava.platform_reported_conversion_value, 0)                      as platform_reported_conversion_value,

        s.date_start                                                             as _extracted_at
    from source s
    left join actions_agg aa
        on  s.date_start  = aa.date_start
        and s.campaign_id = aa.campaign_id
        and s.ad_set_id   = aa.ad_set_id
        and s.ad_id       = aa.ad_id
    left join action_values_agg ava
        on  s.date_start  = ava.date_start
        and s.campaign_id = ava.campaign_id
        and s.ad_set_id   = ava.ad_set_id
        and s.ad_id       = ava.ad_id
)

select
    spend_date,
    campaign_id,
    meta_campaign_id,
    ad_set_id,
    ad_id,
    spend_amount_local,
    impressions,
    clicks,
    reach,
    link_clicks,
    platform_reported_conversions,
    platform_reported_conversion_value,
    {{ add_audit_columns(
        source_system='meta_ads',
        source_id_column="campaign_id || '_' || coalesce(ad_set_id, 'null') || '_' || coalesce(ad_id, 'null') || '_' || cast(spend_date as varchar)",
        business_columns=['campaign_id', 'ad_set_id', 'ad_id', 'spend_date'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
