{{ config(materialized='view') }}

-- Meta Ads individual ad metadata. One row per ad.
-- Note: Fivetran uses adset_id (not ad_set_id) as the FK column name from the Meta API.
-- Volatile creative attributes (link URL, headline, image) are kept as raw strings;
-- structured creative analytics are a v2 concern.

with source as (
    select * from {{ source('meta_ads', 'ads') }}
),

renamed as (
    select
        cast(id        as varchar)                                               as ad_id,
        cast(adset_id  as varchar)                                               as ad_set_id,
        'meta_' || cast(campaign_id as varchar)                                  as campaign_id,
        cast(campaign_id as varchar)                                             as meta_campaign_id,
        cast(name      as varchar)                                               as ad_name,

        cast(status    as varchar)                                               as ad_status,
        (cast(status as varchar) = 'ACTIVE')                                     as is_active,

        cast(creative_id as varchar)                                             as creative_id,

        cast(created_time as timestamp_tz)                                       as created_at,
        cast(updated_time as timestamp_tz)                                       as updated_at,

        coalesce(cast(updated_time as timestamp_tz), cast(created_time as timestamp_tz)) as _extracted_at
    from source
)

select
    ad_id,
    ad_set_id,
    campaign_id,
    meta_campaign_id,
    ad_name,
    ad_status,
    is_active,
    creative_id,
    created_at,
    updated_at,
    {{ add_audit_columns(
        source_system='meta_ads',
        source_id_column='ad_id',
        business_columns=['ad_id', 'updated_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
