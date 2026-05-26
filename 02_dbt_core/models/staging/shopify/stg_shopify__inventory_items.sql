{{ config(materialized='view') }}

with source as (
    select * from {{ source('shopify', 'inventory_items') }}
),

renamed as (
    select
        cast(id         as varchar)                                              as inventory_item_id,
        cast(sku        as varchar)                                              as sku,

        -- Unit cost — optional per §6.4; NULL means cost is not tracked for this SKU.
        cast(cost as numeric(18, 6))                                             as unit_cost,

        -- country of origin for customs and duty classification
        cast(country_code_of_origin     as varchar)                              as country_of_origin,
        cast(province_code_of_origin    as varchar)                              as province_of_origin,
        cast(harmonized_system_code     as varchar)                              as hs_code,

        cast(tracked   as boolean)                                               as inventory_tracked,
        cast(requires_shipping as boolean)                                       as requires_shipping,

        cast(created_at as timestamp_tz)                                         as created_at,
        cast(updated_at as timestamp_tz)                                         as updated_at,

        updated_at                                                               as _extracted_at
    from source
)

select
    inventory_item_id,
    sku,
    unit_cost,
    country_of_origin,
    province_of_origin,
    hs_code,
    inventory_tracked,
    requires_shipping,
    created_at,
    updated_at,
    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='inventory_item_id',
        business_columns=['inventory_item_id', 'updated_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
