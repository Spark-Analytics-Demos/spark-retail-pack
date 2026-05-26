{{ config(materialized='view') }}

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

renamed as (
    select
        cast(date_start    as date)                                              as spend_date,
        'meta_' || cast(campaign_id as varchar)                                  as campaign_id,
        cast(campaign_id   as varchar)                                           as meta_campaign_id,
        cast(ad_set_id     as varchar)                                           as ad_set_id,
        cast(ad_id         as varchar)                                           as ad_id,

        -- spend is already in account currency decimal (not cents for insights)
        cast(spend as numeric(18, 6))                                            as spend_amount_local,

        cast(impressions as int)                                                 as impressions,
        cast(clicks      as int)                                                 as clicks,
        cast(coalesce(reach, 0) as int)                                          as reach,

        -- unique clicks (link clicks, not all clicks)
        cast(coalesce(inline_link_clicks, 0) as int)                             as link_clicks,

        -- platform-reported conversions from actions array (VARIANT path)
        -- Fivetran connector users: see connector note above — may need a separate join
        coalesce(
            (
                select sum(try_cast(a.value:value as numeric(18, 6)))
                from lateral flatten(
                    input  => try_parse_json(cast({{ source_col('meta_ads', 'daily_insights', 'actions_raw', 'actions') }} as varchar)),
                    outer  => true
                ) a
                where a.value:action_type::varchar = 'purchase'
            ),
            0
        )::numeric(18, 6)                                                        as platform_reported_conversions,

        coalesce(
            (
                select sum(try_cast(av.value:value as numeric(18, 6)))
                from lateral flatten(
                    input  => try_parse_json(cast({{ source_col('meta_ads', 'daily_insights', 'action_values_raw', 'action_values') }} as varchar)),
                    outer  => true
                ) av
                where av.value:action_type::varchar = 'purchase'
            ),
            0
        )::numeric(18, 6)                                                        as platform_reported_conversion_value,

        date_start                                                               as _extracted_at
    from source
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
