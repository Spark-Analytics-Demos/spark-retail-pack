{{ config(materialized='view') }}

-- Stripe disputes are chargebacks initiated by the cardholder (not the merchant).
-- They are NOT in stripe.refunds; they have their own table.
-- Both disputes and refunds feed fact_refunds; is_chargeback = true identifies disputes (§6.5).
-- Amounts in cents; divided by 100 in staging.

with source as (
    select * from {{ source('stripe', 'disputes') }}
),

renamed as (
    select
        cast(id     as varchar)                                                  as dispute_id,
        cast(charge as varchar)                                                  as charge_id,

        -- amount in cents → decimal (§6.5)
        cast(amount as numeric(18, 6)) / 100                                     as dispute_amount,
        upper(cast(currency as varchar))                                         as currency_code,

        cast(status as varchar)                                                  as dispute_status,
        cast(reason as varchar)                                                  as dispute_reason,

        cast(true as boolean)                                                    as is_chargeback,

        cast(created as timestamp_tz)                                            as dispute_timestamp,

        cast(created as timestamp_tz)                                            as _extracted_at
    from source
)

select
    dispute_id,
    charge_id,
    dispute_amount,
    currency_code,
    dispute_status,
    dispute_reason,
    is_chargeback,
    dispute_timestamp,
    {{ add_audit_columns(
        source_system='stripe',
        source_id_column='dispute_id',
        business_columns=['dispute_id', 'charge_id'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
