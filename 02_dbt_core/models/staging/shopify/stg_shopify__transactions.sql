{{ config(materialized='view') }}

with source as (
    select * from {{ source('shopify', 'transactions') }}
),

renamed as (
    select
        cast(id       as varchar)                                                as transaction_id,
        cast(order_id as varchar)                                                as order_id,

        -- transaction type and outcome
        cast(kind   as varchar)                                                  as transaction_kind,
        cast(status as varchar)                                                  as transaction_status,

        -- gateway and payment method (feeds dim_payment_method)
        -- Connector note: Fivetran flattens payment_details into separate columns
        -- (payment_details_credit_card_company, etc.). Airbyte/raw API connectors
        -- keep payment_details as VARIANT; override via source_mapping_overrides.
        cast(gateway as varchar)                                                 as payment_gateway,
        cast({{ source_col('shopify', 'transactions', 'card_brand',     'payment_details_credit_card_company')          }} as varchar) as card_brand,
        cast({{ source_col('shopify', 'transactions', 'card_bin',       'payment_details_credit_card_bin')              }} as varchar) as card_bin,
        cast({{ source_col('shopify', 'transactions', 'card_exp_month', 'payment_details_credit_card_expiration_month') }} as varchar) as card_exp_month,
        cast({{ source_col('shopify', 'transactions', 'card_exp_year',  'payment_details_credit_card_expiration_year')  }} as varchar) as card_exp_year,
        cast({{ source_col('shopify', 'transactions', 'digital_wallet', 'payment_details_credit_card_wallet')           }} as varchar) as digital_wallet,

        -- amounts
        cast(amount   as numeric(18, 6))                                         as transaction_amount,
        cast(currency as varchar)                                                as currency_code,
        cast(coalesce(maximum_refundable, 0) as numeric(18, 6))                 as maximum_refundable,

        -- authorization
        cast(authorization as varchar)                                           as authorization_code,
        cast(error_code    as varchar)                                           as error_code,
        cast(message       as varchar)                                           as error_message,

        -- relationships
        cast(parent_id as varchar)                                               as parent_transaction_id,

        -- timestamps
        cast(created_at as timestamp_tz)                                         as created_at,
        cast(processed_at as timestamp_tz)                                       as processed_at,

        created_at                                                               as _extracted_at
    from source
    where status = 'success'  -- keep only successful transactions; failed/pending excluded at staging
)

select
    transaction_id,
    order_id,
    transaction_kind,
    transaction_status,
    payment_gateway,
    card_brand,
    card_bin,
    card_exp_month,
    card_exp_year,
    digital_wallet,
    transaction_amount,
    currency_code,
    maximum_refundable,
    authorization_code,
    error_code,
    error_message,
    parent_transaction_id,
    created_at,
    processed_at,
    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='transaction_id',
        business_columns=['transaction_id', 'order_id'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
