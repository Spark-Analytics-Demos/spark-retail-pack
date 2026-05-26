{{ config(materialized='view') }}

-- Klaviyo automated email flows (welcome series, abandoned cart, post-purchase, etc.).
-- Combined with stg_klaviyo__campaigns into dim_email_campaign with campaign_type = 'flow'.
-- Flows are reusable (no single send_date); triggered by customer actions or segment criteria.

with source as (
    select * from {{ source('klaviyo', 'flows') }}
),

renamed as (
    select
        cast(id   as varchar)                                                    as flow_id,
        cast(name as varchar)                                                    as flow_name,
        cast(status as varchar)                                                  as flow_status,

        'flow'                                                                   as campaign_type,

        cast(trigger_type as varchar)                                            as trigger_type,

        -- flows have no single send_date — NULL per design (§6.8)
        cast(null as date)                                                       as send_date,

        (cast(status as varchar) = 'live')                                       as is_active,

        cast(created as timestamp_tz)                                            as created_at,
        cast(coalesce(
            cast({{ source_col('klaviyo', 'flows', 'updated', 'updated') }} as timestamp_tz),
            cast(created as timestamp_tz)
        ) as timestamp_tz)                                                       as updated_at,

        coalesce(
            cast({{ source_col('klaviyo', 'flows', 'updated', 'updated') }} as timestamp_tz),
            cast(created as timestamp_tz)
        )                                                                        as _extracted_at
    from source
)

select
    flow_id,
    flow_name,
    flow_status,
    campaign_type,
    trigger_type,
    send_date,
    is_active,
    created_at,
    updated_at,
    {{ add_audit_columns(
        source_system='klaviyo',
        source_id_column='flow_id',
        business_columns=['flow_id', 'updated_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
