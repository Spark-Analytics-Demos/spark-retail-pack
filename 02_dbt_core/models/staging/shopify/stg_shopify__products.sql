{{ config(materialized='view') }}

with source as (
    select * from {{ source('shopify', 'products') }}
),

renamed as (
    select
        cast(id     as varchar)                                                  as product_id,
        cast(title  as varchar)                                                  as product_title,
        cast(handle as varchar)                                                  as product_handle,

        -- taxonomy
        cast(product_type as varchar)                                            as product_type,
        cast(vendor       as varchar)                                            as vendor,

        -- active/archived
        cast(status = 'active' as boolean)                                       as is_active,
        cast(status as varchar)                                                  as product_status,
        cast(published_at as timestamp_tz)                                       as published_at,

        -- image (primary product image)
        -- Connector note: Fivetran exposes image_url as a flattened column; VARIANT
        -- connectors use image:src::varchar. Override via source_mapping_overrides if needed.
        cast({{ source_col('shopify', 'products', 'image_url', 'image_url') }} as varchar) as image_url,

        -- tags
        cast(tags as varchar)                                                    as product_tags_raw,

        -- body_html (stripped downstream; not used analytically)
        cast(body_html as varchar)                                               as body_html,

        -- timestamps
        cast(created_at as timestamp_tz)                                         as created_at,
        cast(updated_at as timestamp_tz)                                         as updated_at,

        updated_at                                                               as _extracted_at
    from source
)

select
    product_id,
    product_title,
    product_handle,
    product_type,
    vendor,
    is_active,
    product_status,
    published_at,
    image_url,
    product_tags_raw,
    body_html,
    created_at,
    updated_at,
    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='product_id',
        business_columns=['product_id', 'updated_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
