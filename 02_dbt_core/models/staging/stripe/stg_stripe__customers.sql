{{ config(materialized='view') }}

-- Connector note: Fivetran and Airbyte both convert Stripe's Unix epoch timestamps to
-- TIMESTAMP automatically. Amount fields are NOT present on customers — they live on charges.

with source as (
    select * from {{ source('stripe', 'customers') }}
),

renamed as (
    select
        cast(id as varchar)                                                      as stripe_customer_id,

        -- PII hashed per §8.5; email hash is the cross-source join key (ADR-003)
        {{ pii_mask('email', method='hash') }}                                   as customer_email_hash,
        {{ pii_mask('phone', method='hash') }}                                   as phone_hash,
        {{ pii_mask('name',  method='hash') }}                                   as name_hash,

        cast(coalesce(delinquent, false) as boolean)                             as is_delinquent,
        cast(coalesce(livemode,   true)  as boolean)                             as is_live,

        cast(created    as timestamp_tz)                                         as created_at,

        cast(created    as timestamp_tz)                                         as _extracted_at
    from source
)

select
    stripe_customer_id,
    customer_email_hash,
    phone_hash,
    name_hash,
    is_delinquent,
    is_live,
    created_at,
    {{ add_audit_columns(
        source_system='stripe',
        source_id_column='stripe_customer_id',
        business_columns=['stripe_customer_id', 'created_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
