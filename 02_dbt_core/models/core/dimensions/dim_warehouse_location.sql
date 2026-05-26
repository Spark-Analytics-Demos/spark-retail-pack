{{ config(materialized='table') }}

-- Warehouse / fulfillment location dimension from Shopify per §4.9.
-- One row per Shopify location. Type 1 — history not tracked.

with source as (
    select
        location_id,
        location_name,
        is_active,
        is_legacy,
        city,
        province_code                     as state_or_region,
        country_code,
        coalesce(fulfillment_service, '')  as fulfillment_service,
        created_at,
        _extracted_at
    from {{ ref('stg_shopify__locations') }}
)

select
    {{ generate_dim_sk(['location_id']) }}  as location_sk,
    location_id,
    location_name,

    -- location_type heuristic: 3PL when Shopify delegates to a fulfillment service,
    -- otherwise default to warehouse (POS store detection requires POS data)
    case
        when fulfillment_service != '' and fulfillment_service != 'manual'
            then '3pl'
        when is_legacy
            then 'store'
        else 'warehouse'
    end                                    as location_type,

    country_code,
    state_or_region,
    city,
    -- timezone not available from Shopify locations API; use reporting default
    cast('{{ var("reporting_timezone", "UTC") }}' as varchar)  as timezone,
    -- is_fulfillment_location: true unless it's a legacy location
    (not is_legacy or is_active)           as is_fulfillment_location,
    is_active,
    created_at,
    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='location_id',
        business_columns=['location_id', 'location_name'],
        extracted_at_column='_extracted_at'
    ) }}
from source
