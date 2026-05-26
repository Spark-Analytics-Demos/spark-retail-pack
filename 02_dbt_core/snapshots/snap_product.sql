{% snapshot snap_product %}

{{
    config(
        target_schema='snapshots',
        strategy='timestamp',
        unique_key='variant_id',
        updated_at='updated_at',
        invalidate_hard_deletes=False
    )
}}

with base as (
    select
        v.variant_id,
        v.product_id,
        v.sku,
        v.variant_title,
        v.barcode,
        v.unit_price,
        v.compare_at_price,
        v.inventory_item_id,
        v.inventory_policy,
        v.requires_shipping,
        v.is_taxable,
        v.weight,
        v.weight_unit,
        v.created_at,

        p.product_title,
        p.product_handle,
        p.product_type,
        p.vendor,
        p.is_active,
        p.product_status,
        p.image_url,
        p.product_tags_raw,

        ii.unit_cost,
        ii.country_of_origin,
        ii.inventory_tracked,

        -- GREATEST returns NULL if any arg is NULL (Snowflake behaviour).
        -- Outer coalesce guards against an orphan variant where p is unmatched.
        coalesce(
            greatest(
                coalesce(v.updated_at, v.created_at),
                coalesce(p.updated_at, p.created_at)
            ),
            coalesce(v.updated_at, v.created_at)
        ) as updated_at
    from {{ ref('stg_shopify__product_variants') }} v
    left join {{ ref('stg_shopify__products') }} p
        on v.product_id = p.product_id
    left join {{ ref('stg_shopify__inventory_items') }} ii
        on v.inventory_item_id = ii.inventory_item_id
)

select * from base

{% endsnapshot %}
