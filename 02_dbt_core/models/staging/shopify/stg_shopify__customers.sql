{{ config(materialized='view') }}

-- Connector note: default column names assume Fivetran's Shopify connector, which flattens
-- nested address objects (e.g. default_address_country_code). Airbyte and raw API deployments
-- keep these as a VARIANT column; override via source_mapping_overrides in dbt_project.yml:
--   shopify__customers.field_mappings.country_code: "default_address:country_code"

with source as (
    select * from {{ source('shopify', 'customers') }}
),

renamed as (
    select
        -- keys
        cast({{ source_col('shopify', 'customers', 'customer_id', 'id') }} as varchar)                as shopify_customer_id,

        -- email: hashed immediately per §8.5; hash is the canonical cross-source join key (ADR-003)
        {{ pii_mask(source_col('shopify', 'customers', 'customer_email', 'email'), method='hash') }}  as customer_email_hash,

        -- phone: hashed for Tier-2 identity matching (ADR-003)
        {{ pii_mask('phone', method='hash') }}                                                         as phone_hash,

        -- name PII: hashed; never stored in plaintext
        {{ pii_mask('first_name', method='hash') }}                                                    as first_name_hash,
        {{ pii_mask('last_name',  method='hash') }}                                                    as last_name_hash,

        -- canonical customer status mapped from Shopify's state field (§6.4)
        case
            when state = 'enabled'  then 'active'
            when state = 'disabled' then 'blocked'
            when state = 'declined' then 'blocked'
            when state = 'invited'  then 'active'
            else coalesce(cast(state as varchar), 'unknown')
        end                                                                                            as customer_status,
        cast(state as varchar)                                                                         as shopify_customer_state,

        -- marketing consent (Klaviyo overrides email_subscribed in int_customer_identity_resolution)
        cast(coalesce(accepts_marketing,     false) as boolean)                                        as marketing_consent,
        cast(coalesce(accepts_marketing,     false) as boolean)                                        as email_subscribed,
        cast(coalesce(accepts_sms_marketing, false) as boolean)                                        as sms_subscribed,

        -- geography from default_address (Fivetran-flattened column names by default)
        cast({{ source_col('shopify', 'customers', 'country_code',  'default_address_country_code')  }} as varchar) as country_code,
        cast({{ source_col('shopify', 'customers', 'province_code', 'default_address_province_code') }} as varchar) as province_code,
        -- address PII hashed per §8.5
        {{ pii_mask(source_col('shopify', 'customers', 'city',        'default_address_city'), method='hash') }} as city_hash,
        {{ pii_mask(source_col('shopify', 'customers', 'postal_code', 'default_address_zip'),  method='hash') }} as postal_code_hash,
        cast({{ source_col('shopify', 'customers', 'company', 'default_address_company') }} as varchar)          as company,

        -- B2B detection: LIKE used to handle Shopify's "tag1, tag2" spacing (§6.4)
        (
            lower(coalesce(cast(tags as varchar), '')) like '%b2b%'
            or lower(coalesce(cast(tags as varchar), '')) like '%wholesale%'
            or lower(coalesce(cast(tags as varchar), '')) like '%business%'
            or (
                cast({{ source_col('shopify', 'customers', 'company', 'default_address_company') }} as varchar) is not null
                and length(trim(cast({{ source_col('shopify', 'customers', 'company', 'default_address_company') }} as varchar))) > 0
            )
        )                                                                                              as is_b2b_customer,

        cast(tags         as varchar)                                                                  as customer_tags_raw,
        cast(note         as varchar)                                                                  as customer_note,
        cast(orders_count as int)                                                                      as orders_count,
        cast(total_spent  as numeric(18, 6))                                                           as total_spent,
        cast(created_at   as timestamp_tz)                                                             as created_at,
        cast(updated_at   as timestamp_tz)                                                             as updated_at,

        updated_at                                                                                     as _extracted_at
    from source
)

select
    shopify_customer_id,
    customer_email_hash,
    phone_hash,
    first_name_hash,
    last_name_hash,
    customer_status,
    shopify_customer_state,
    marketing_consent,
    email_subscribed,
    sms_subscribed,
    country_code,
    province_code,
    city_hash,
    postal_code_hash,
    company,
    is_b2b_customer,
    customer_tags_raw,
    customer_note,
    orders_count,
    total_spent,
    created_at,
    updated_at,
    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='shopify_customer_id',
        business_columns=['shopify_customer_id', 'updated_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
