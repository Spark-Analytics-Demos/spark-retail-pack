{{ config(materialized='view') }}

-- GA4 user-level metadata. Cross-referenced with dim_customer where user_id is set.
-- user_pseudo_id is device-scoped; the same person on phone and desktop appears twice.
-- user_id is set only when the site implements GA4's User-ID feature (§6.6).
--
-- Connector note: Fivetran's BigQuery connector synthesizes this table from GA4's
-- user-scoped fields. Some connectors may not provide it; if absent, customer linkage
-- falls back to purchase event transaction_id matching.

with source as (
    select * from {{ source('ga4', 'users') }}
),

renamed as (
    select
        cast(user_pseudo_id as varchar)                                          as user_pseudo_id,
        cast(user_id        as varchar)                                          as user_id,

        -- first/last seen dates: Fivetran typically exposes these from GA4 user properties
        cast({{ source_col('ga4', 'users', 'first_seen_date', 'first_seen_date') }} as date) as first_seen_date,
        cast({{ source_col('ga4', 'users', 'last_seen_date',  'last_seen_date')  }} as date) as last_seen_date,

        current_timestamp()                                                      as _extracted_at
    from source
)

select
    user_pseudo_id,
    user_id,
    first_seen_date,
    last_seen_date,
    {{ add_audit_columns(
        source_system='ga4',
        source_id_column='user_pseudo_id',
        business_columns=['user_pseudo_id'],
        extracted_at_column='current_timestamp()'
    ) }}
from renamed
