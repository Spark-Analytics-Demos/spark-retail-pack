{{ config(materialized='table') }}

-- Geographic reference dimension from seeds/dim_geography.csv per §4.7.
-- One row per country (country-level) or country+region (sub-region level).
-- Static; rebuilt only when the seed changes.

with seed as (
    select
        cast(geography_id         as varchar)  as geography_id,
        cast(country_code         as varchar)  as country_code,
        cast(country_name         as varchar)  as country_name,
        cast(country_region       as varchar)  as country_region,
        cast(country_subregion    as varchar)  as country_subregion,
        cast(state_or_region_code as varchar)  as state_or_region_code,
        cast(state_or_region_name as varchar)  as state_or_region_name,
        cast(default_currency     as varchar)  as default_currency,
        cast(default_timezone     as varchar)  as default_timezone,
        cast(is_tax_jurisdiction  as boolean)  as is_tax_jurisdiction,
        current_timestamp()                    as _extracted_at
    from {{ ref('dim_geography') }}
)

select
    {{ generate_dim_sk(['geography_id']) }}  as geography_sk,
    geography_id,
    country_code,
    country_name,
    country_region,
    country_subregion,
    state_or_region_code,
    state_or_region_name,
    default_currency,
    default_timezone,
    is_tax_jurisdiction,
    {{ add_audit_columns(
        source_system='seeds',
        source_id_column='geography_id',
        business_columns=['geography_id', 'country_code'],
        extracted_at_column='_extracted_at'
    ) }}
from seed
