{{ config(materialized='view') }}

-- Daily per-SKU stock history. Mirrors stg_shopify__inventory_levels but carries
-- a snapshot_date so fact_inventory_snapshot can build a real historical series
-- (one row per inventory_item x location x day) instead of a single current snapshot.
-- Only the stock position is taken from this feed; inventory value, days-of-supply
-- and OOS/Pro flags are (re)computed downstream from the canonical unit_cost and
-- trailing sales, keeping one methodology across all snapshot modes.

with source as (
    select * from {{ source('shopify', 'inventory_snapshots') }}
),

renamed as (
    select
        cast(inventory_item_id as varchar)                                      as inventory_item_id,
        cast(location_id       as varchar)                                      as location_id,
        cast(snapshot_date     as date)                                         as snapshot_date,

        cast(available as int)                                                  as quantity_available,

        -- This feed has no `incoming`; Shopify's PO feature is out of scope here.
        cast(0 as int)                                                          as quantity_incoming,

        cast(updated_at as timestamp_tz)                                        as updated_at,
        updated_at                                                              as _extracted_at
    from source
)

select
    inventory_item_id,
    location_id,
    snapshot_date,
    quantity_available,
    quantity_incoming,
    updated_at,
    {{ add_audit_columns(
        source_system='shopify',
        source_id_column="inventory_item_id || '_' || location_id || '_' || cast(snapshot_date as varchar)",
        business_columns=['inventory_item_id', 'location_id', 'snapshot_date'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
