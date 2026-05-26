{{ config(materialized='view') }}

-- Klaviyo one-time email campaign sends. Combined with stg_klaviyo__flows into
-- dim_email_campaign with campaign_type = 'campaign' (§6.8).

with source as (
    select * from {{ source('klaviyo', 'campaigns') }}
),

renamed as (
    select
        cast(id      as varchar)                                                 as campaign_id,
        cast(name    as varchar)                                                 as campaign_name,
        cast(subject as varchar)                                                 as subject_line,
        cast(status  as varchar)                                                 as campaign_status,

        'campaign'                                                               as campaign_type,

        -- send_time is null for drafted/scheduled campaigns that haven't sent yet
        cast(send_time as timestamp_tz)                                          as sent_at,
        cast(send_time as date)                                                  as send_date,

        cast(coalesce(num_recipients, 0) as int)                                 as audience_size,

        (cast(status as varchar) = 'sent')                                       as is_sent,

        cast(created as timestamp_tz)                                            as created_at,
        cast(coalesce(
            cast({{ source_col('klaviyo', 'campaigns', 'updated', 'updated') }} as timestamp_tz),
            cast(created as timestamp_tz)
        ) as timestamp_tz)                                                       as updated_at,

        coalesce(
            cast({{ source_col('klaviyo', 'campaigns', 'updated', 'updated') }} as timestamp_tz),
            cast(created as timestamp_tz)
        )                                                                        as _extracted_at
    from source
)

select
    campaign_id,
    campaign_name,
    subject_line,
    campaign_status,
    campaign_type,
    sent_at,
    send_date,
    audience_size,
    is_sent,
    created_at,
    updated_at,
    {{ add_audit_columns(
        source_system='klaviyo',
        source_id_column='campaign_id',
        business_columns=['campaign_id', 'updated_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
