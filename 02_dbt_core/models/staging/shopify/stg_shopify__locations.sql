{{ config(materialized='view') }}

with source as (
    select * from {{ source('shopify', 'locations') }}
),

renamed as (
    select
        cast(id   as varchar)                                                    as location_id,
        cast(name as varchar)                                                    as location_name,

        -- location type heuristic: if legacy_id is null it's a fulfillment service location
        cast(active as boolean)                                                  as is_active,
        cast(legacy as boolean)                                                  as is_legacy,

        -- address
        cast(address1    as varchar)                                             as address_line_1,
        cast(address2    as varchar)                                             as address_line_2,
        cast(city        as varchar)                                             as city,
        cast(zip         as varchar)                                             as postal_code,
        cast(province    as varchar)                                             as province,
        cast(province_code as varchar)                                           as province_code,
        cast(country     as varchar)                                             as country_name,
        cast(country_code as varchar)                                            as country_code,
        cast(phone       as varchar)                                             as phone,

        -- fulfillment service (null for owned locations)
        cast(fulfillment_service as varchar)                                     as fulfillment_service,
        cast(local_pickup_settings_instructions as varchar)                      as pickup_instructions,

        cast(created_at as timestamp_tz)                                         as created_at,
        cast(updated_at as timestamp_tz)                                         as updated_at,

        updated_at                                                               as _extracted_at
    from source
)

select
    location_id,
    location_name,
    is_active,
    is_legacy,
    address_line_1,
    address_line_2,
    city,
    postal_code,
    province,
    province_code,
    country_name,
    country_code,
    phone,
    fulfillment_service,
    pickup_instructions,
    created_at,
    updated_at,
    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='location_id',
        business_columns=['location_id', 'updated_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
