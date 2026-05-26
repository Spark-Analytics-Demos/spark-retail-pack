{{ config(materialized='view') }}

-- Connector note: Fivetran flattens the card sub-object into separate columns
-- (card_brand, card_last4, card_exp_month, card_exp_year, card_wallet).
-- Airbyte/raw API connectors keep card as VARIANT; override via source_mapping_overrides.

with source as (
    select * from {{ source('stripe', 'payment_methods') }}
),

renamed as (
    select
        cast(id       as varchar)                                                as payment_method_id,
        cast(customer as varchar)                                                as stripe_customer_id,

        cast(type as varchar)                                                    as payment_method_type,

        -- card details (Fivetran flattens card sub-object; VARIANT connectors override)
        cast({{ source_col('stripe', 'payment_methods', 'card_brand',     'card_brand')     }} as varchar) as card_brand,
        cast({{ source_col('stripe', 'payment_methods', 'card_last4',     'card_last4')     }} as varchar) as card_last4,
        cast({{ source_col('stripe', 'payment_methods', 'card_exp_month', 'card_exp_month') }} as varchar) as card_exp_month,
        cast({{ source_col('stripe', 'payment_methods', 'card_exp_year',  'card_exp_year')  }} as varchar) as card_exp_year,
        cast({{ source_col('stripe', 'payment_methods', 'card_wallet',    'card_wallet')    }} as varchar) as card_wallet,
        cast({{ source_col('stripe', 'payment_methods', 'card_funding',   'card_funding')   }} as varchar) as card_funding,
        cast({{ source_col('stripe', 'payment_methods', 'card_country',   'card_country')   }} as varchar) as card_country,

        cast(coalesce(livemode, true) as boolean)                                as is_live,

        cast(created as timestamp_tz)                                            as created_at,

        cast(created as timestamp_tz)                                            as _extracted_at
    from source
    where coalesce(livemode, true) = true  -- exclude test-mode payment methods
)

select
    payment_method_id,
    stripe_customer_id,
    payment_method_type,
    card_brand,
    card_last4,
    card_exp_month,
    card_exp_year,
    card_wallet,
    card_funding,
    card_country,
    is_live,
    created_at,
    {{ add_audit_columns(
        source_system='stripe',
        source_id_column='payment_method_id',
        business_columns=['payment_method_id', 'created_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
