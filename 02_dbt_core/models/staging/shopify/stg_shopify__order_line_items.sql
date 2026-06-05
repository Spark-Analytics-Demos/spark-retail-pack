{{ config(materialized='table') }}

with source as (
    select * from {{ source('shopify', 'order_line_items') }}
),

-- Snowflake does not support LATERAL FLATTEN inside a scalar subquery.
-- Aggregate tax per line item in a separate CTE, then join back.
tax_agg as (
    select
        cast(id as varchar)                                                      as line_item_id,
        coalesce(
            sum(try_cast(t.value:price::varchar as numeric(18, 6))),
            0
        )::numeric(18, 6)                                                        as line_tax
    from source,
        lateral flatten(
            input => try_parse_json(cast(tax_lines as varchar)),
            outer => true
        ) t
    group by 1
),

renamed as (
    select
        cast(s.id       as varchar)                                              as line_item_id,
        cast(s.order_id as varchar)                                              as order_id,

        -- product identifiers
        cast(nullif(cast(s.variant_id as varchar), '0') as varchar)             as variant_id,
        cast(s.product_id as varchar)                                            as product_id,
        cast(s.sku as varchar)                                                   as sku,
        cast(s.name as varchar)                                                  as line_item_name,
        cast(s.title as varchar)                                                 as product_title_at_sale,
        cast(s.variant_title as varchar)                                         as variant_title_at_sale,

        -- quantities and amounts
        cast(s.quantity as int)                                                  as quantity,
        cast(s.price as numeric(18, 6))                                          as unit_price,
        cast(s.quantity * cast(s.price as numeric(18, 6)) as numeric(18, 6))   as line_subtotal,
        cast(coalesce(s.total_discount, 0) as numeric(18, 6))                   as line_discount,
        cast(
            s.quantity * cast(s.price as numeric(18, 6))
            - coalesce(s.total_discount, 0)
        as numeric(18, 6))                                                       as line_net_amount,
        cast(coalesce(s.total_discount, 0) > 0 as boolean)                      as was_promotional,

        coalesce(ta.line_tax, 0)::numeric(18, 6)                                as line_tax,

        -- fulfillment
        cast(s.fulfillment_status as varchar)                                    as fulfillment_status,
        cast(s.requires_shipping  as boolean)                                    as requires_shipping,
        cast(s.taxable            as boolean)                                    as is_taxable,
        cast(s.gift_card          as boolean)                                    as is_gift_card,

        -- custom line attributes (freeform merchant metadata)
        try_parse_json(cast(s.properties as varchar))                            as line_properties,

        cast(s.vendor as varchar)                                                as vendor
    from source s
    left join tax_agg ta on cast(s.id as varchar) = ta.line_item_id
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
