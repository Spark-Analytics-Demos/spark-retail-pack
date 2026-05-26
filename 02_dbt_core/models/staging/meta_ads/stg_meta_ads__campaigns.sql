{{ config(materialized='view') }}

-- Meta Ads campaign master. One row per campaign.
-- Budget amounts are in the ad account's smallest currency unit (cents for USD);
-- staging divides by 100 (§6.7).
-- Campaign ID is prefixed with 'meta_' for cross-platform uniqueness in dim_marketing_campaign.

with source as (
    select * from {{ source('meta_ads', 'campaigns') }}
),

renamed as (
    select
        'meta_' || cast(id as varchar)                                           as campaign_id,
        cast(id         as varchar)                                              as meta_campaign_id,
        cast(account_id as varchar)                                              as account_id,
        cast(name       as varchar)                                              as campaign_name,

        -- objective mapped as-is; downstream dimension handles canonical mapping
        cast(objective    as varchar)                                            as campaign_objective,
        cast(status       as varchar)                                            as campaign_status,
        cast(buying_type  as varchar)                                            as buying_type,

        -- budgets: Meta stores in smallest currency unit; divide by 100 (§6.7)
        cast(coalesce(daily_budget,    0) as numeric(18, 6)) / 100              as daily_budget,
        cast(coalesce(lifetime_budget, 0) as numeric(18, 6)) / 100              as lifetime_budget,

        cast(start_time as timestamp_tz)                                         as start_at,
        cast(stop_time  as timestamp_tz)                                         as end_at,
        cast(start_time as date)                                                 as start_date,
        cast(stop_time  as date)                                                 as end_date,

        (cast(status as varchar) = 'ACTIVE')                                     as is_active,

        cast(created_time as timestamp_tz)                                       as created_at,
        cast(updated_time as timestamp_tz)                                       as updated_at,

        coalesce(cast(updated_time as timestamp_tz), cast(created_time as timestamp_tz)) as _extracted_at
    from source
)

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
    {{ add_audit_columns(
        source_system='meta_ads',
        source_id_column='campaign_id',
        business_columns=['campaign_id', 'updated_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
