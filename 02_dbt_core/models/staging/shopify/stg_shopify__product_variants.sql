{{ config(materialized='view') }}

with source as (
    select * from {{ source('shopify', 'product_variants') }}
),

renamed as (
    select
        cast(id         as varchar)                                              as variant_id,
        cast(product_id as varchar)                                              as product_id,

        -- SKU and display
        cast(sku         as varchar)                                             as sku,
        cast(title       as varchar)                                             as variant_title,
        cast(barcode     as varchar)                                             as barcode,
        cast(option1     as varchar)                                             as option_1,
        cast(option2     as varchar)                                             as option_2,
        cast(option3     as varchar)                                             as option_3,

        -- pricing
        cast(price             as numeric(18, 6))                                as unit_price,
        cast(compare_at_price  as numeric(18, 6))                                as compare_at_price,

        -- inventory linkage (joins to stg_shopify__inventory_items for cost/barcode)
        cast(inventory_item_id as varchar)                                       as inventory_item_id,
        cast(inventory_management as varchar)                                    as inventory_management,
        cast(inventory_policy     as varchar)                                    as inventory_policy,
        cast(inventory_quantity   as int)                                        as inventory_quantity,
        cast(old_inventory_quantity as int)                                      as old_inventory_quantity,

        -- fulfillment
        cast(requires_shipping as boolean)                                       as requires_shipping,
        cast(taxable           as boolean)                                       as is_taxable,
        cast(fulfillment_service as varchar)                                     as fulfillment_service,

        -- physical attributes
        cast(weight      as numeric(10, 4))                                      as weight,
        cast(weight_unit as varchar)                                             as weight_unit,

        -- image
        cast(image_id as varchar)                                                as variant_image_id,

        -- timestamps
        cast(created_at as timestamp_tz)                                         as created_at,
        cast(updated_at as timestamp_tz)                                         as updated_at,

        updated_at                                                               as _extracted_at
    from source
)

select
    variant_id,
    product_id,
    sku,
    variant_title,
    barcode,
    option_1,
    option_2,
    option_3,
    unit_price,
    compare_at_price,
    inventory_item_id,
    inventory_management,
    inventory_policy,
    inventory_quantity,
    old_inventory_quantity,
    requires_shipping,
    is_taxable,
    fulfillment_service,
    weight,
    weight_unit,
    variant_image_id,
    created_at,
    updated_at,
    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='variant_id',
        business_columns=['variant_id', 'updated_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
