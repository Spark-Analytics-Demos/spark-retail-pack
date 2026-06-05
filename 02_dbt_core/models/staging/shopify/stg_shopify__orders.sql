{{ config(materialized='view') }}

with source as (
    select * from {{ source('shopify', 'orders') }}
),

note_attrs as (
    -- Extract UTM parameters from Shopify's note_attributes JSON array.
    -- Fivetran/Airbyte stores note_attributes as a VARIANT column.
    -- Clients whose connector creates a separate table for note attributes
    -- should override by wrapping in a custom intermediate model and
    -- setting source_mapping_overrides for the utm_* fields.
    select
        cast({{ source_col('shopify', 'orders', 'order_id', 'id') }} as varchar)               as order_id,
        max(case when f.value:name::varchar = 'utm_source'   then f.value:value::varchar end)  as utm_source,
        max(case when f.value:name::varchar = 'utm_medium'   then f.value:value::varchar end)  as utm_medium,
        max(case when f.value:name::varchar = 'utm_campaign' then f.value:value::varchar end)  as utm_campaign,
        max(case when f.value:name::varchar = 'utm_content'  then f.value:value::varchar end)  as utm_content,
        max(case when f.value:name::varchar = 'utm_term'     then f.value:value::varchar end)  as utm_term
    from source,
    lateral flatten(
        input  => try_parse_json(coalesce(cast(note_attributes as varchar), '[]')),
        outer  => true
    ) f
    group by 1
),

renamed as (
    select
        -- keys
        cast(s.{{ source_col('shopify', 'orders', 'order_id', 'id') }} as varchar)                    as order_id,
        cast(coalesce(s.name, cast(s.order_number as varchar)) as varchar)                             as order_number,
        cast(nullif(cast(s.customer_id as varchar), '0') as varchar)                                  as shopify_customer_id,

        -- timestamps (order_date derived in reporting timezone)
        cast(s.created_at as timestamp_tz)                                                             as order_timestamp,
        convert_timezone(
            '{{ var("reporting_timezone") }}',
            cast(s.created_at as timestamp_tz)
        )::date                                                                                        as order_date,
        cast(s.updated_at   as timestamp_tz)                                                           as updated_at,
        cast(s.cancelled_at as timestamp_tz)                                                           as cancelled_at,
        cast(s.closed_at    as timestamp_tz)                                                           as closed_at,
        cast(s.processed_at as timestamp_tz)                                                           as processed_at,

        -- customer contact — hash only; no plain email in staging per §8.5
        {{ pii_mask('s.' ~ source_col('shopify', 'orders', 'customer_email', 'email'), method='hash') }} as customer_email_hash_at_order,

        -- canonical order_status per §6.4 status-mapping table
        case
            when s.cancelled_at is not null                                       then 'cancelled'
            when s.financial_status = 'refunded'                                  then 'refunded'
            when s.financial_status = 'partially_refunded'                        then 'partial_refund'
            when s.financial_status = 'voided'                                    then 'cancelled'
            when s.financial_status in ('paid', 'partially_paid')
                 and s.fulfillment_status = 'fulfilled'                           then 'fulfilled'
            when s.financial_status in ('paid', 'partially_paid')                 then 'paid'
            when s.financial_status in ('pending', 'authorized')                  then 'pending'
            else 'unknown'
        end                                                                                            as order_status,
        cast(s.financial_status   as varchar)                                                          as financial_status,
        cast(s.fulfillment_status as varchar)                                                          as fulfillment_status,

        -- monetary amounts
        cast(s.{{ source_col('shopify', 'orders', 'gross_amount',    'subtotal_price')  }} as numeric(18, 6)) as gross_amount,
        cast(s.{{ source_col('shopify', 'orders', 'discount_amount', 'total_discounts') }} as numeric(18, 6)) as discount_amount,
        cast(s.{{ source_col('shopify', 'orders', 'tax_amount',      'total_tax')       }} as numeric(18, 6)) as tax_amount,
        -- shipping_amount default: Fivetran flattens total_shipping_price_set as a separate column.
        -- Airbyte / VARIANT-based connectors: override via source_mapping_overrides:
        --   shopify__orders.field_mappings.shipping_amount: "total_shipping_price_set:shop_money:amount"
        cast(s.{{ source_col('shopify', 'orders', 'shipping_amount', 'total_shipping_price_set_shop_money_amount') }} as numeric(18, 6)) as shipping_amount,
        cast(coalesce(s.total_tip_received, 0) as numeric(18, 6))                                     as tip_amount,
        cast(s.{{ source_col('shopify', 'orders', 'net_amount', 'total_price') }} as numeric(18, 6))  as net_amount,
        cast(s.currency as varchar)                                                                    as original_currency_code,

        -- channel / attribution
        cast(s.source_name      as varchar)                                                            as source_name,
        cast(s.landing_site     as varchar)                                                            as landing_page_url,
        cast(s.landing_site_ref as varchar)                                                            as referrer_url,
        cast(s.cart_token       as varchar)                                                            as cart_id,

        -- UTM (extracted from note_attrs CTE above)
        n.utm_source,
        n.utm_medium,
        n.utm_campaign,
        n.utm_content,
        n.utm_term,

        -- device (from client_details; Fivetran flattens to client_details_browser_width etc.)
        -- Connector note: Airbyte/raw API connectors expose client_details as VARIANT;
        -- override via source_mapping_overrides for VARIANT-path syntax.
        case
            when try_cast(s.{{ source_col('shopify', 'orders', 'browser_width', 'client_details_browser_width') }} as int) < 768   then 'mobile'
            when try_cast(s.{{ source_col('shopify', 'orders', 'browser_width', 'client_details_browser_width') }} as int) < 1024  then 'tablet'
            when try_cast(s.{{ source_col('shopify', 'orders', 'browser_width', 'client_details_browser_width') }} as int) >= 1024 then 'desktop'
        end                                                                                            as device_category,
        cast(s.{{ source_col('shopify', 'orders', 'user_agent', 'client_details_user_agent') }} as varchar) as user_agent,
        -- IP hashed immediately; never stored in plaintext per §8.5
        {{ pii_mask('s.browser_ip', method='hash') }}                                                  as ip_address_hash,

        -- flags
        cast(coalesce(s.test, false) as boolean)                                                        as is_test_order,
        -- Tag match uses LIKE to avoid false negatives from Shopify's "tag1, tag2" spacing
        (
            lower(coalesce(cast(s.source_name as varchar), '')) = 'recharge'
            or lower(coalesce(cast(s.tags as varchar), '')) like '%subscription%'
        )                                                                                               as is_subscription_order,

        -- tags / metadata
        cast(s.tags as varchar)                                                                         as tags_raw,
        cast(s.note as varchar)                                                                         as note,
        try_parse_json(cast(s.discount_codes as varchar))                                              as discount_codes_raw,
        try_cast(s.discount_codes[0]:code::varchar as varchar)                                         as primary_discount_code,

        -- geography from shipping / billing addresses
        -- Connector note: Fivetran flattens address objects (shipping_address_country_code,
        -- shipping_address_province_code, billing_address_country_code). Airbyte/raw API
        -- connectors keep these as VARIANT; override via source_mapping_overrides.
        cast(s.{{ source_col('shopify', 'orders', 'shipping_country_code',  'shipping_address_country_code')  }} as varchar) as shipping_country_code,
        cast(s.{{ source_col('shopify', 'orders', 'shipping_province_code', 'shipping_address_province_code') }} as varchar) as shipping_province_code,
        cast(s.{{ source_col('shopify', 'orders', 'billing_country_code',   'billing_address_country_code')   }} as varchar) as billing_country_code,

        s.updated_at                                                                                   as _extracted_at

    from source s
    left join note_attrs n
        on n.order_id = cast(s.{{ source_col('shopify', 'orders', 'order_id', 'id') }} as varchar)

    -- Filter test orders per §6.4 edge cases
    where coalesce(s.test, false) = false
      and s.created_at::date >= '{{ var("min_order_date", "2020-01-01") }}'
)

select
    order_id,
    order_number,
    shopify_customer_id,
    order_timestamp,
    order_date,
    updated_at,
    cancelled_at,
    closed_at,
    processed_at,
    customer_email_hash_at_order,
    order_status,
    financial_status,
    fulfillment_status,
    gross_amount,
    discount_amount,
    tax_amount,
    shipping_amount,
    tip_amount,
    net_amount,
    original_currency_code,
    source_name,
    landing_page_url,
    referrer_url,
    cart_id,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_content,
    utm_term,
    device_category,
    user_agent,
    ip_address_hash,
    is_test_order,
    is_subscription_order,
    tags_raw,
    note,
    discount_codes_raw,
    primary_discount_code,
    shipping_country_code,
    shipping_province_code,
    billing_country_code,
    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='order_id',
        business_columns=['order_id', 'updated_at'],
        extracted_at_column='_extracted_at'
    ) }}
from renamed
