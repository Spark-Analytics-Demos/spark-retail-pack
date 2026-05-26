{{ config(materialized='table') }}

-- Customer identity dimension from snap_customer (SCD2) per §4.3.
-- One row per resolved customer per version. PII columns masked via pii_mask().
-- Sources: Shopify + Stripe + Klaviyo, identity-resolved via int_customer_identity_resolution.
--
-- Stubbed NULL columns (require downstream data):
--   first_order_date — populated after fact_orders is built (fact→dim update in mart layer)
--   last_seen_at     — populated after fact tables are built
--   customer_segment — NULL in OSS; advanced RFM assignment is a Pro feature
--   acquisition_channel — NULL; derived from acquisition_source_system in a later phase
--   city, preferred_currency — not available in source systems

with snapshot as (
    select
        customer_id,
        shopify_customer_id,
        stripe_customer_id,
        klaviyo_profile_id,
        email_hash,
        phone_hash,
        first_name_hash,
        last_name_hash,
        customer_status,
        is_b2b_customer,
        country_code,
        province_code,
        postal_code_hash,
        company,
        customer_tags_raw,
        email_subscribed,
        sms_subscribed,
        marketing_consent,
        source_systems,
        identity_resolution_method,
        match_confidence,
        acquisition_source_system,
        acquisition_date,
        created_at,
        updated_at,
        dbt_valid_from,
        dbt_valid_to,
        _extracted_at
    from {{ ref('snap_customer') }}
)

select
    {{ generate_dim_sk(['customer_id'], 'dbt_valid_from') }}  as customer_sk,
    customer_id,

    -- email: hash column (SHA-256 when masking on; plaintext when masking off per §8.5)
    email_hash,
    -- email plaintext: NULL when masking enabled; plaintext (= email_hash value) when disabled
    {{ pii_mask('email_hash', method='null') }}               as email,

    phone_hash,
    {{ pii_mask('phone_hash', method='null') }}               as phone,

    -- names: hashed when masking on; plaintext (= *_hash value) when masking off
    {{ pii_mask('first_name_hash', method='null') }}          as first_name,
    {{ pii_mask('last_name_hash', method='null') }}           as last_name,

    customer_status,

    -- Pro feature: advanced RFM segmentation — NULL in OSS
    cast(null as varchar)                                     as customer_segment,

    -- acquisition channel: requires channel-source join — NULL until Phase 2
    cast(null as varchar)                                     as acquisition_channel,
    acquisition_source_system,
    acquisition_date,

    -- requires fact_orders — stubbed NULL until facts are built
    cast(null as date)                                        as first_order_date,
    -- requires multiple fact tables — stubbed NULL until facts are built
    cast(null as timestamp_tz)                                as last_seen_at,

    is_b2b_customer,

    -- tags: split comma-separated raw string to array
    case
        when customer_tags_raw is not null and trim(customer_tags_raw) != ''
            then split(customer_tags_raw, ',')
        else array_construct()
    end                                                       as customer_tags,

    -- preferred_currency: not available in source systems — NULL
    cast(null as varchar)                                     as preferred_currency,

    country_code,
    province_code                                             as region,
    -- city: not captured in identity resolution sources — NULL
    cast(null as varchar)                                     as city,
    postal_code_hash,

    marketing_consent,
    email_subscribed,
    sms_subscribed,

    source_systems,
    identity_resolution_method,
    match_confidence,

    created_at,
    updated_at,

    -- SCD2 columns
    dbt_valid_from                                            as valid_from,
    dbt_valid_to                                              as valid_to,
    (dbt_valid_to is null)                                    as is_current,

    {{ add_audit_columns(
        source_system='shopify',
        source_id_column='customer_id',
        business_columns=['customer_id', 'email_hash'],
        extracted_at_column='_extracted_at'
    ) }}
from snapshot
