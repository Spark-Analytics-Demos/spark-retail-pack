{{ config(materialized='view') }}

-- Stripe refunds are payment-processor-initiated returns (customer-requested or merchant-initiated).
-- Chargebacks (cardholder disputes) live in stg_stripe__disputes.
-- Both are merged into fact_refunds in the intermediate layer (is_chargeback distinguishes them).
-- Amounts in cents; divided by 100 in staging (§6.5).

with source as (
    select * from {{ source('stripe', 'refunds') }}
),

renamed as (
    select
        cast(id     as varchar)                                                  as refund_id,
        cast(charge as varchar)                                                  as charge_id,

        -- amount in cents → decimal (§6.5)
        cast(amount as numeric(18, 6)) / 100                                     as refund_amount,
        upper(cast(currency as varchar))                                         as currency_code,

        cast(status as varchar)                                                  as refund_status,
        cast(reason as varchar)                                                  as refund_reason,

        cast(false as boolean)                                                   as is_chargeback,

        cast(created as timestamp_tz)                                            as refund_timestamp,

        cast(created as timestamp_tz)                                            as _extracted_at
    from source
    where cast(status as varchar) = 'succeeded'
)

select
    refund_id,
    charge_id,
    refund_amount,
    currency_code,
    refund_status,
    refund_reason,
    is_chargeback,
    refund_timestamp,
    {{ add_audit_columns(
        source_system='stripe',
        source_id_column='refund_id',
        business_columns=['refund_id', 'charge_id'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
