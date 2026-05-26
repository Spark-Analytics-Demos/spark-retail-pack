{{ config(materialized='view') }}

-- Klaviyo customer profiles. Cross-referenced with dim_customer via email hash (ADR-003).
-- Klaviyo is the primary source for email_subscribed, sms_subscribed, and marketing_consent
-- — these override Shopify values in int_customer_identity_resolution (§6.8).
--
-- Connector note: Klaviyo's consent fields evolved across API versions.
-- Fivetran's connector (as of 2024) exposes:
--   email_marketing__consent (or subscriptions__email__marketing__consent)
--   sms_marketing__consent   (or subscriptions__sms__marketing__consent)
-- Use source_mapping_overrides to point to the correct column for your connector version.

with source as (
    select * from {{ source('klaviyo', 'profiles') }}
),

renamed as (
    select
        cast(id as varchar)                                                      as klaviyo_profile_id,

        -- PII hashed per §8.5; email hash is the cross-source join key (ADR-003)
        {{ pii_mask('email',        method='hash') }}                            as customer_email_hash,
        {{ pii_mask('phone_number', method='hash') }}                            as phone_hash,
        {{ pii_mask('first_name',   method='hash') }}                            as first_name_hash,
        {{ pii_mask('last_name',    method='hash') }}                            as last_name_hash,

        -- consent: Klaviyo wins over Shopify for these fields (§6.8)
        -- Fivetran default column names; override if your connector version differs
        cast(
            coalesce(
                cast({{ source_col('klaviyo', 'profiles', 'email_consent', 'email_marketing__consent') }} as varchar),
                'never_subscribed'
            ) = 'subscribed'
        as boolean)                                                              as email_subscribed,

        cast(
            coalesce(
                cast({{ source_col('klaviyo', 'profiles', 'sms_consent', 'sms_marketing__consent') }} as varchar),
                'never_subscribed'
            ) = 'subscribed'
        as boolean)                                                              as sms_subscribed,

        -- marketing_consent: true if subscribed to either channel
        cast(
            coalesce(
                cast({{ source_col('klaviyo', 'profiles', 'email_consent', 'email_marketing__consent') }} as varchar),
                'never_subscribed'
            ) = 'subscribed'
            or
            coalesce(
                cast({{ source_col('klaviyo', 'profiles', 'sms_consent', 'sms_marketing__consent') }} as varchar),
                'never_subscribed'
            ) = 'subscribed'
        as boolean)                                                              as marketing_consent,

        cast(created as timestamp_tz)                                            as created_at,
        cast(coalesce(
            cast({{ source_col('klaviyo', 'profiles', 'updated', 'updated') }} as timestamp_tz),
            cast(created as timestamp_tz)
        ) as timestamp_tz)                                                       as updated_at,

        coalesce(
            cast({{ source_col('klaviyo', 'profiles', 'updated', 'updated') }} as timestamp_tz),
            cast(created as timestamp_tz)
        )                                                                        as _extracted_at
    from source
)

select
    klaviyo_profile_id,
    customer_email_hash,
    phone_hash,
    first_name_hash,
    last_name_hash,
    email_subscribed,
    sms_subscribed,
    marketing_consent,
    created_at,
    updated_at,
    {{ add_audit_columns(
        source_system='klaviyo',
        source_id_column='klaviyo_profile_id',
        business_columns=['klaviyo_profile_id', 'updated_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
