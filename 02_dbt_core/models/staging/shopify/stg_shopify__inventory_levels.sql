{{ config(materialized='view') }}

with source as (
    select * from {{ source('shopify', 'inventory_levels') }}
),

renamed as (
    select
        cast(inventory_item_id as varchar)                                       as inventory_item_id,
        cast(location_id       as varchar)                                       as location_id,

        -- Shopify reports `available` (net sellable) separately from `incoming`.
        -- `committed` = on-hand minus available; computed downstream via open orders.
        cast(available as int)                                                   as quantity_available,

        -- `incoming` is only populated when the Purchase Orders feature is active.
        cast(coalesce(incoming, 0) as int)                                       as quantity_incoming,

        cast(updated_at as timestamp_tz)                                         as updated_at,

        updated_at                                                               as _extracted_at
    from source
)

select
    inventory_item_id,
    location_id,
    quantity_available,
    quantity_incoming,
    updated_at,
    {{ add_audit_columns(
        source_system='shopify',
        source_id_column="inventory_item_id || '_' || location_id",
        business_columns=['inventory_item_id', 'location_id', 'updated_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
