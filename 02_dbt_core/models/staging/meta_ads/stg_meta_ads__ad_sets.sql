{{ config(materialized='view') }}

-- Meta Ads ad set master. One row per ad set.
-- Ad sets are the targeting layer between campaigns and individual ads.
-- Budget amounts divided by 100 (same cents convention as campaigns).

with source as (
    select * from {{ source('meta_ads', 'ad_sets') }}
),

renamed as (
    select
        cast(id          as varchar)                                             as ad_set_id,
        'meta_' || cast(campaign_id as varchar)                                 as campaign_id,
        cast(campaign_id as varchar)                                             as meta_campaign_id,
        cast(name        as varchar)                                             as ad_set_name,

        cast(status      as varchar)                                             as ad_set_status,
        (cast(status as varchar) = 'ACTIVE')                                     as is_active,

        -- budget: cents → decimal
        cast(coalesce(daily_budget, 0) as numeric(18, 6)) / 100                 as daily_budget,
        cast(coalesce(bid_amount,   0) as numeric(18, 6)) / 100                 as bid_amount,

        cast(billing_event   as varchar)                                         as billing_event,
        cast(optimization_goal as varchar)                                       as optimization_goal,

        cast(start_time as timestamp_tz)                                         as start_at,
        cast(end_time   as timestamp_tz)                                         as end_at,
        cast(start_time as date)                                                 as start_date,
        cast(end_time   as date)                                                 as end_date,

        cast(created_time as timestamp_tz)                                       as created_at,
        cast(updated_time as timestamp_tz)                                       as updated_at,

        coalesce(cast(updated_time as timestamp_tz), cast(created_time as timestamp_tz)) as _extracted_at
    from source
)

select
    ad_set_id,
    campaign_id,
    meta_campaign_id,
    ad_set_name,
    ad_set_status,
    is_active,
    daily_budget,
    bid_amount,
    billing_event,
    optimization_goal,
    start_at,
    end_at,
    start_date,
    end_date,
    created_at,
    updated_at,
    {{ add_audit_columns(
        source_system='meta_ads',
        source_id_column='ad_set_id',
        business_columns=['ad_set_id', 'updated_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
