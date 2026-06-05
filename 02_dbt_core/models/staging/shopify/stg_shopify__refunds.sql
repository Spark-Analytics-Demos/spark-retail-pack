{{ config(materialized='view') }}

with source as (
    select * from {{ source('shopify', 'refunds') }}
),

renamed as (
    select
        cast(id       as varchar)                                                as refund_id,
        cast(order_id as varchar)                                                as order_id,

        -- timestamps
        cast(created_at as timestamp_tz)                                         as refund_timestamp,
        convert_timezone(
            '{{ var("reporting_timezone") }}',
            cast(created_at as timestamp_tz)
        )::date                                                                  as refund_date,
        cast(processed_at as timestamp_tz)                                       as processed_at,

        -- refund detail
        cast(note as varchar)                                                    as refund_note,
        cast(restock as boolean)                                                 as is_restock,

        -- refund_line_items VARIANT array — line-level refunds; unwound in int_orders_enriched
        try_parse_json(cast(refund_line_items as varchar))                       as refund_line_items,

        -- transactions VARIANT array — payment-side refunds; amount summed downstream
        try_parse_json(cast(transactions as varchar))                            as refund_transactions,

        created_at                                                               as _extracted_at
    from source
)

select
    refund_id,
    order_id,
    refund_timestamp,
    refund_date,
    processed_at,
    refund_note,
    is_restock,
    refund_line_items,
    refund_transactions,
    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='refund_id',
        business_columns=['refund_id', 'order_id'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
