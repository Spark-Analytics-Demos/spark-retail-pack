{{ config(materialized='view') }}

-- Connector note: Fivetran flattens payment_method_details into separate columns
-- (payment_method_details_type, payment_method_details_card_brand, etc.).
-- Airbyte/raw API connectors keep payment_method_details as VARIANT;
-- override via source_mapping_overrides in dbt_project.yml.
-- Stripe stores amounts in integer cents; staging divides by 100 (§6.5).
-- Stripe's created field is converted to TIMESTAMP by the ingestion tool.

with source as (
    select * from {{ source('stripe', 'charges') }}
),

renamed as (
    select
        cast(id       as varchar)                                                as charge_id,
        cast(customer as varchar)                                                as stripe_customer_id,

        -- amounts: cents → decimal (§6.5)
        cast(amount          as numeric(18, 6)) / 100                           as charge_amount,
        cast(coalesce(amount_refunded, 0) as numeric(18, 6)) / 100              as amount_refunded,

        -- currency: Stripe sends lowercase ISO 4217; normalize to uppercase
        upper(cast(currency as varchar))                                         as currency_code,

        cast(status as varchar)                                                  as charge_status,

        -- payment method: Fivetran flattens payment_method_details sub-object
        cast({{ source_col('stripe', 'charges', 'payment_type',   'payment_method_details_type')           }} as varchar) as payment_type,
        cast({{ source_col('stripe', 'charges', 'card_brand',     'payment_method_details_card_brand')     }} as varchar) as card_brand,
        cast({{ source_col('stripe', 'charges', 'card_last4',     'payment_method_details_card_last4')     }} as varchar) as card_last4,
        cast({{ source_col('stripe', 'charges', 'card_exp_month', 'payment_method_details_card_exp_month') }} as varchar) as card_exp_month,
        cast({{ source_col('stripe', 'charges', 'card_exp_year',  'payment_method_details_card_exp_year')  }} as varchar) as card_exp_year,
        cast({{ source_col('stripe', 'charges', 'card_wallet',    'payment_method_details_card_wallet')    }} as varchar) as card_wallet,

        -- Shopify linkage via charge metadata (Fivetran flattens metadata.shopify_order_id)
        cast({{ source_col('stripe', 'charges', 'shopify_order_id', 'metadata_shopify_order_id') }} as varchar) as shopify_order_id,

        cast(payment_method as varchar)                                          as payment_method_id,

        cast(coalesce(paid,     false) as boolean)                               as is_paid,
        cast(coalesce(captured, false) as boolean)                               as is_captured,
        cast(coalesce(refunded, false) as boolean)                               as is_refunded,

        cast(created as timestamp_tz)                                            as charge_timestamp,

        cast(created as timestamp_tz)                                            as _extracted_at
    from source
    where coalesce(livemode, false) = true  -- exclude test-mode charges (§6.5)
)

select
    charge_id,
    stripe_customer_id,
    charge_amount,
    amount_refunded,
    currency_code,
    charge_status,
    payment_type,
    card_brand,
    card_last4,
    card_exp_month,
    card_exp_year,
    card_wallet,
    shopify_order_id,
    payment_method_id,
    is_paid,
    is_captured,
    is_refunded,
    charge_timestamp,
    {{ add_audit_columns(
        source_system='stripe',
        source_id_column='charge_id',
        business_columns=['charge_id', 'charge_timestamp'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
