{{ config(materialized='table') }}

-- Product variant dimension from snap_product (SCD2) per §4.4.
-- One row per variant per version. Adds category/subcategory from the
-- product_category_mapping seed and derives display_name and brand.
-- Variants without a SKU are excluded per the design spec (SKU is the natural key).

with snapshot as (
    select
        variant_id,
        product_id,
        sku,
        variant_title,
        barcode,
        product_handle,
        image_url,
        product_title,
        product_type,
        vendor,
        is_active,
        product_status,
        product_tags_raw,
        unit_price,
        compare_at_price,
        unit_cost,
        inventory_policy,
        requires_shipping,
        is_taxable,
        weight,
        weight_unit,
        inventory_tracked,
        created_at,
        updated_at,
        dbt_valid_from,
        dbt_valid_to,
        _extracted_at
    from {{ ref('snap_product') }}
    where sku is not null
),

category_map as (
    select
        cast(product_type as varchar)  as product_type,
        cast(category     as varchar)  as category,
        cast(subcategory  as varchar)  as subcategory
    from {{ ref('product_category_mapping') }}
),

enriched as (
    select
        s.*,
        coalesce(cm.category,    'Uncategorized')  as category,
        coalesce(cm.subcategory, 'Uncategorized')  as subcategory
    from snapshot s
    left join category_map cm on s.product_type = cm.product_type
)

select
    {{ generate_dim_sk(['variant_id'], 'dbt_valid_from') }}  as product_sk,
    sku,
    product_id,
    variant_id,
    product_title,
    variant_title,

    -- display_name: "Product Title - Variant Title" or just "Product Title" for single-variant
    case
        when variant_title is not null and variant_title != 'Default Title'
            then product_title || ' - ' || variant_title
        else product_title
    end                                                       as display_name,

    barcode,
    product_handle,
    image_url,
    product_type,
    category,
    subcategory,
    vendor,
    vendor                                                    as brand,
    split(coalesce(product_tags_raw, ''), ',')                as tags,
    unit_price,
    compare_at_price,
    unit_cost,
    cast('{{ var("reporting_currency", "USD") }}' as varchar) as currency_code,
    weight,
    weight_unit,
    is_taxable,
    requires_shipping,
    is_active,
    inventory_tracked,
    inventory_policy,
    created_at,
    updated_at,

    -- SCD2 columns
    dbt_valid_from                                            as valid_from,
    dbt_valid_to                                              as valid_to,
    (dbt_valid_to is null)                                    as is_current,

    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='variant_id',
        business_columns=['variant_id', 'sku'],
        extracted_at_column='_extracted_at'
    ) }}
from enriched
