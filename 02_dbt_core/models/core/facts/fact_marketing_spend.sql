{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['campaign_id', 'spend_date'],
    on_schema_change='append_new_columns',
    cluster_by=['spend_date', 'campaign_sk']
) }}

-- fact_marketing_spend per §4.22. One row per campaign per day.
-- Source: stg_meta_ads__daily_insights (ad-level). Aggregated here to campaign/day grain.
-- campaign_sk: SCD2-aware join to dim_marketing_campaign at spend_date.
-- channel_sk: all Meta campaigns map to dim_channel.channel_id = 'paid_social_meta'.
-- geography_sk: NULL in v1 — geo-targeted breakdown requires ad-set level data.
-- FX: Meta account currency → reporting currency via daily_fx_rate.
-- Lookback: 7 days — Meta retroactively adjusts spend within attribution windows.

with daily_insights as (
    select * from {{ ref('stg_meta_ads__daily_insights') }}
    {{ incremental_lookback('spend_date', 'fact_marketing_spend') }}
),

-- Aggregate from ad-level to campaign/day grain
campaign_day as (
    select
        campaign_id,
        spend_date,
        sum(spend_amount_local)                                         as spend_amount_local,
        sum(impressions)                                                as impressions,
        sum(clicks)                                                     as clicks,
        sum(platform_reported_conversions)                              as conversions_reported_by_platform,
        sum(platform_reported_conversion_value)                         as conversion_value_reported_by_platform,
        -- Assume Meta account currency = reporting currency for v1.
        -- Multi-currency Meta accounts: set source_mapping_overrides.meta_ads__daily_insights
        -- to include an account_currency column and pass it here.
        cast('{{ var("reporting_currency", "USD") }}' as varchar)       as account_currency,
        max(cast(spend_date as timestamp_tz))                           as _extracted_at
    from daily_insights
    group by campaign_id, spend_date
),

-- SCD2-aware campaign lookup: dim version active on spend_date
campaign_lookup as (
    select
        campaign_sk,
        campaign_id,
        valid_from,
        valid_to
    from {{ ref('dim_marketing_campaign') }}
),

-- All Meta campaigns use the paid_social_meta channel
channel_lookup as (
    select channel_sk
    from {{ ref('dim_channel') }}
    where channel_id = 'paid_social_meta'
),

-- FX rate validity intervals (same LEAD-window pattern as fact_orders)
fx_intervals as (
    select
        from_currency,
        rate_date                                                       as valid_from,
        lead(rate_date) over (
            partition by from_currency, to_currency
            order by rate_date
        )                                                               as valid_to,
        rate
    from {{ ref('fx_rates') }}
    where to_currency = '{{ var("reporting_currency", "USD") }}'
),

campaign_day_fx as (
    select
        cd.*,
        coalesce(
            fx.rate,
            case when upper(cd.account_currency) = '{{ var("reporting_currency", "USD") }}'
                 then 1.0
                 else null
            end
        )::numeric(18,8)                                                as fx_rate
    from campaign_day cd
    left join fx_intervals fx
        on upper(cd.account_currency) = fx.from_currency
        and cd.spend_date::date >= fx.valid_from
        and (fx.valid_to is null or cd.spend_date::date < fx.valid_to)
)

select
    {{ generate_dim_sk(['cd.campaign_id', 'cd.spend_date']) }}          as spend_sk,
    dc.campaign_sk,
    cd.campaign_id,
    ch.channel_sk,
    cast(null as varchar)                                               as geography_sk,

    cd.spend_date,
    -- date_sk: YYYYMMDD integer matching dim_date surrogate key
    year(cd.spend_date) * 10000
        + month(cd.spend_date) * 100
        + day(cd.spend_date)                                            as date_sk,

    -- Spend in reporting currency
    cast(cd.spend_amount_local
         * coalesce(cd.fx_rate, 1.0)
         as numeric(18,4))                                              as spend_amount,
    cast('{{ var("reporting_currency", "USD") }}' as varchar)           as currency_code,
    cd.account_currency                                                 as original_currency_code,
    cast(cd.spend_amount_local as numeric(18,4))                        as original_spend_amount,

    -- Engagement metrics
    cd.impressions,
    cd.clicks,

    -- Platform-reported conversions (kept for reference; canonical attribution uses warehouse data)
    cast(cd.conversions_reported_by_platform as numeric(18,0))          as conversions_reported_by_platform,
    cast(cd.conversion_value_reported_by_platform as numeric(18,4))     as conversion_value_reported_by_platform,

    current_timestamp()                                                 as loaded_at,

    {{ add_audit_columns(
        source_system='meta_ads',
        source_id_column="cd.campaign_id || '_' || cast(cd.spend_date as varchar)",
        business_columns=['cd.campaign_id', 'cd.spend_date'],
        extracted_at_column='cd._extracted_at'
    ) }}

from campaign_day_fx cd
-- SCD2-correct campaign: version active on spend_date
left join campaign_lookup dc
    on dc.campaign_id = cd.campaign_id
    and cd.spend_date >= dc.valid_from::date
    and (cd.spend_date < dc.valid_to::date or dc.valid_to is null)
cross join channel_lookup ch
