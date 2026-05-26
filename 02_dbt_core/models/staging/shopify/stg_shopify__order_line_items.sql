{{ config(materialized='view') }}

with source as (
    select * from {{ source('shopify', 'order_line_items') }}
),

renamed as (
    select
        cast(id       as varchar)                                                as line_item_id,
        cast(order_id as varchar)                                                as order_id,

        -- product identifiers
        cast(nullif(cast(variant_id as varchar), '0') as varchar)               as variant_id,
        cast(product_id as varchar)                                              as product_id,
        cast(sku as varchar)                                                     as sku,
        cast(name as varchar)                                                    as line_item_name,
        cast(title as varchar)                                                   as product_title_at_sale,
        cast(variant_title as varchar)                                           as variant_title_at_sale,

        -- quantities and amounts
        cast(quantity as int)                                                    as quantity,
        cast(price as numeric(18, 6))                                            as unit_price,
        cast(quantity * cast(price as numeric(18, 6)) as numeric(18, 6))        as line_subtotal,
        cast(coalesce(total_discount, 0) as numeric(18, 6))                     as line_discount,
        cast(
            quantity * cast(price as numeric(18, 6))
            - coalesce(total_discount, 0)
        as numeric(18, 6))                                                       as line_net_amount,
        cast(coalesce(total_discount, 0) > 0 as boolean)                        as was_promotional,

        -- tax (aggregated from tax_lines VARIANT array)
        coalesce(
            (
                select sum(try_cast(t.value:price as numeric(18, 6)))
                from lateral flatten(
                    input => try_parse_json(cast(tax_lines as varchar)),
                    outer => true
                ) t
            ),
            0
        )::numeric(18, 6)                                                        as line_tax,

        -- fulfillment
        cast(fulfillment_status as varchar)                                      as fulfillment_status,
        cast(requires_shipping  as boolean)                                      as requires_shipping,
        cast(taxable            as boolean)                                      as is_taxable,
        cast(gift_card          as boolean)                                      as is_gift_card,

        -- custom line attributes (freeform merchant metadata)
        cast(properties as variant)                                              as line_properties,

        cast(vendor as varchar)                                                  as vendor

        -- No source updated_at on line items; extraction time used for _extracted_at in audit footer.
        -- Fivetran users may replace current_timestamp() with _fivetran_synced for more accuracy.
    from source
)

select
    line_item_id,
    order_id,
    variant_id,
    product_id,
    sku,
    line_item_name,
    product_title_at_sale,
    variant_title_at_sale,
    quantity,
    unit_price,
    line_subtotal,
    line_discount,
    line_net_amount,
    was_promotional,
    line_tax,
    fulfillment_status,
    requires_shipping,
    is_taxable,
    is_gift_card,
    line_properties,
    vendor,
    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='line_item_id',
        business_columns=['line_item_id', 'order_id'],
        extracted_at_column='current_timestamp()'
    ) }}
from renamed
