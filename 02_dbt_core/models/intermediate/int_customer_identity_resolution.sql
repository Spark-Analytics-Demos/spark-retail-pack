{{ config(materialized='ephemeral') }}

-- Three-tier customer identity resolution per ADR-003 and §4.3.
-- Produces one row per resolved customer.
--   Tier 1: email hash match (high confidence) — customer_id = email_hash
--   Tier 2: phone hash match (high confidence) — inherits email customer_id where possible
--   Tier 3: fuzzy name+address via EDITDISTANCE (medium confidence)
--            gated by var('fuzzy_matching_enabled', true)
--            only produces matches when pii_masking_enabled=false (plaintext in *_hash cols)
-- Source priority for attributes: Shopify > Stripe > Klaviyo except consent (Klaviyo wins).

with shopify as (
    select
        shopify_customer_id,
        customer_email_hash,
        phone_hash,
        first_name_hash,
        last_name_hash,
        customer_status,
        is_b2b_customer,
        marketing_consent,
        email_subscribed,
        sms_subscribed,
        country_code,
        province_code,
        postal_code_hash,
        company,
        customer_tags_raw,
        created_at,
        updated_at
    from {{ ref('stg_shopify__customers') }}
),

stripe as (
    select
        stripe_customer_id,
        customer_email_hash,
        phone_hash,
        created_at,
        created_at as updated_at
    from {{ ref('stg_stripe__customers') }}
    where is_live = true
),

klaviyo as (
    select
        klaviyo_profile_id,
        customer_email_hash,
        phone_hash,
        first_name_hash,
        last_name_hash,
        email_subscribed,
        sms_subscribed,
        marketing_consent,
        created_at,
        updated_at
    from {{ ref('stg_klaviyo__profiles') }}
),

-- Full attribute set across all sources (NULLs where source doesn't provide the field)
all_records as (
    select
        'shopify'           as source_system,
        shopify_customer_id as source_id,
        customer_email_hash,
        phone_hash,
        first_name_hash,
        last_name_hash,
        postal_code_hash,
        country_code,
        province_code,
        customer_status,
        is_b2b_customer,
        marketing_consent,
        email_subscribed,
        sms_subscribed,
        company,
        customer_tags_raw,
        created_at,
        updated_at
    from shopify

    union all

    select
        'stripe',
        stripe_customer_id,
        customer_email_hash,
        phone_hash,
        null::varchar,  -- first_name_hash
        null::varchar,  -- last_name_hash
        null::varchar,  -- postal_code_hash
        null::varchar,  -- country_code
        null::varchar,  -- province_code
        null::varchar,  -- customer_status
        false,          -- is_b2b_customer
        false,          -- marketing_consent
        false,          -- email_subscribed
        false,          -- sms_subscribed
        null::varchar,  -- company
        null::varchar,  -- customer_tags_raw
        created_at,
        updated_at
    from stripe

    union all

    select
        'klaviyo',
        klaviyo_profile_id,
        customer_email_hash,
        phone_hash,
        first_name_hash,
        last_name_hash,
        null::varchar,  -- postal_code_hash
        null::varchar,  -- country_code
        null::varchar,  -- province_code
        null::varchar,  -- customer_status
        false,          -- is_b2b_customer
        marketing_consent,
        email_subscribed,
        sms_subscribed,
        null::varchar,  -- company
        null::varchar,  -- customer_tags_raw
        created_at,
        updated_at
    from klaviyo
),

-- ── TIER 1: Email match ───────────────────────────────────────────────────
-- customer_id = email_hash; records sharing an email_hash are the same customer.
email_assigned as (
    select
        source_system,
        source_id,
        customer_email_hash    as customer_id,
        customer_email_hash,
        phone_hash,
        first_name_hash,
        last_name_hash,
        postal_code_hash,
        country_code,
        province_code,
        customer_status,
        is_b2b_customer,
        marketing_consent,
        email_subscribed,
        sms_subscribed,
        company,
        customer_tags_raw,
        created_at,
        updated_at,
        'email'                as identity_resolution_method,
        'high'                 as match_confidence
    from all_records
    where customer_email_hash is not null
),

-- ── TIER 2: Phone match ───────────────────────────────────────────────────
-- Map phone_hash → customer_id from email-assigned records.
-- Tiebreak on min(customer_id) for the rare case of shared phone across customers.
phone_to_customer as (
    select phone_hash, min(customer_id) as customer_id
    from email_assigned
    where phone_hash is not null
    group by phone_hash
),

-- Records without email: match via phone to get customer_id.
-- If phone not in phone_to_customer, generate phone-scoped customer_id.
phone_assigned as (
    select
        r.source_system,
        r.source_id,
        coalesce(pc.customer_id, 'ph_' || r.phone_hash) as customer_id,
        null::varchar          as customer_email_hash,
        r.phone_hash,
        r.first_name_hash,
        r.last_name_hash,
        r.postal_code_hash,
        r.country_code,
        r.province_code,
        r.customer_status,
        r.is_b2b_customer,
        r.marketing_consent,
        r.email_subscribed,
        r.sms_subscribed,
        r.company,
        r.customer_tags_raw,
        r.created_at,
        r.updated_at,
        'phone'                as identity_resolution_method,
        'high'                 as match_confidence
    from all_records r
    left join phone_to_customer pc on r.phone_hash = pc.phone_hash
    where r.customer_email_hash is null
      and r.phone_hash is not null
),

-- Records with no email and no phone — candidates for Tier 3 or unmatched
no_match_records as (
    select * from all_records
    where customer_email_hash is null
      and phone_hash is null
),

-- ── TIER 3: Fuzzy name+address ────────────────────────────────────────────
{% if var('fuzzy_matching_enabled', true) %}
-- Uses EDITDISTANCE as Jaro-Winkler approximation (Snowflake has no native JW).
-- Requires pii_masking_enabled=false for meaningful results; with masking on,
-- SHA-256 hashes will not satisfy the similarity threshold.
fuzzy_candidates as (
    select
        u.source_system,
        u.source_id,
        e.customer_id,
        u.phone_hash,
        u.first_name_hash,
        u.last_name_hash,
        u.postal_code_hash,
        u.country_code,
        u.province_code,
        u.customer_status,
        u.is_b2b_customer,
        u.marketing_consent,
        u.email_subscribed,
        u.sms_subscribed,
        u.company,
        u.customer_tags_raw,
        u.created_at,
        u.updated_at,
        editdistance(lower(coalesce(u.first_name_hash, '')), lower(coalesce(e.first_name_hash, '')))
        + editdistance(lower(coalesce(u.last_name_hash,  '')), lower(coalesce(e.last_name_hash,  '')))
            as total_name_edit_distance
    from no_match_records u
    cross join (
        select distinct customer_id, first_name_hash, last_name_hash,
                        postal_code_hash, country_code
        from email_assigned
        where source_system = 'shopify'
    ) e
    where
        coalesce(u.first_name_hash, '') != ''
        and coalesce(u.last_name_hash,  '') != ''
        -- First name similarity within threshold
        and editdistance(lower(coalesce(u.first_name_hash, '')), lower(coalesce(e.first_name_hash, '')))::float
            / greatest(length(coalesce(u.first_name_hash, '')), length(coalesce(e.first_name_hash, '')), 1)
            <= 1.0 - {{ var('fuzzy_name_similarity_threshold', 0.92) }}
        -- Last name similarity within threshold
        and editdistance(lower(coalesce(u.last_name_hash, '')),  lower(coalesce(e.last_name_hash, '')))::float
            / greatest(length(coalesce(u.last_name_hash,  '')), length(coalesce(e.last_name_hash,  '')), 1)
            <= 1.0 - {{ var('fuzzy_name_similarity_threshold', 0.92) }}
        {% if var('require_postal_match', true) %}
        and coalesce(u.postal_code_hash, '') != ''
        and left(coalesce(u.postal_code_hash, ''), 5) = left(coalesce(e.postal_code_hash, ''), 5)
        {% endif %}
        and coalesce(u.country_code, '') != ''
        and coalesce(u.country_code, '') = coalesce(e.country_code, '')
),

fuzzy_assigned as (
    select
        source_system,
        source_id,
        customer_id,
        null::varchar          as customer_email_hash,
        phone_hash,
        first_name_hash,
        last_name_hash,
        postal_code_hash,
        country_code,
        province_code,
        customer_status,
        is_b2b_customer,
        marketing_consent,
        email_subscribed,
        sms_subscribed,
        company,
        customer_tags_raw,
        created_at,
        updated_at,
        'fuzzy_name_address'   as identity_resolution_method,
        'medium'               as match_confidence
    from fuzzy_candidates
    qualify row_number() over (
        partition by source_system, source_id
        order by total_name_edit_distance asc
    ) = 1
),

fuzzy_matched_ids as (
    select source_system, source_id from fuzzy_assigned
),
{% endif %}

-- ── Truly unmatched ───────────────────────────────────────────────────────
unmatched as (
    select
        source_system,
        source_id,
        source_system || '_' || source_id as customer_id,
        null::varchar          as customer_email_hash,
        phone_hash,
        first_name_hash,
        last_name_hash,
        postal_code_hash,
        country_code,
        province_code,
        customer_status,
        is_b2b_customer,
        marketing_consent,
        email_subscribed,
        sms_subscribed,
        company,
        customer_tags_raw,
        created_at,
        updated_at,
        'unmatched'            as identity_resolution_method,
        'high'                 as match_confidence
    from no_match_records
    {% if var('fuzzy_matching_enabled', true) %}
    where (source_system, source_id) not in (
        select source_system, source_id from fuzzy_matched_ids
    )
    {% endif %}
),

-- ── Union all tiers ───────────────────────────────────────────────────────
all_assigned as (
    select * from email_assigned
    union all
    select * from phone_assigned
    {% if var('fuzzy_matching_enabled', true) %}
    union all
    select * from fuzzy_assigned
    {% endif %}
    union all
    select * from unmatched
),

-- ── Acquisition source: source with earliest created_at per customer ───────
acquisition as (
    select customer_id, source_system as acquisition_source_system
    from all_assigned
    qualify row_number() over (
        partition by customer_id
        order by created_at asc nulls last, source_system asc
    ) = 1
),

-- ── Aggregate to one row per resolved customer ────────────────────────────
resolved as (
    select
        a.customer_id,

        -- Source IDs
        max(case when a.source_system = 'shopify' then a.source_id end) as shopify_customer_id,
        max(case when a.source_system = 'stripe'  then a.source_id end) as stripe_customer_id,
        max(case when a.source_system = 'klaviyo' then a.source_id end) as klaviyo_profile_id,

        -- Email hash (= customer_id for Tier-1; null for phone/fuzzy/unmatched)
        max(a.customer_email_hash)                                       as email_hash,

        -- Phone: Shopify first, then Stripe, then Klaviyo
        coalesce(
            max(case when a.source_system = 'shopify' then a.phone_hash end),
            max(case when a.source_system = 'stripe'  then a.phone_hash end),
            max(case when a.source_system = 'klaviyo' then a.phone_hash end)
        )                                                                as phone_hash,

        -- Names: Shopify preferred, fallback to Klaviyo
        coalesce(
            max(case when a.source_system = 'shopify' then a.first_name_hash end),
            max(case when a.source_system = 'klaviyo' then a.first_name_hash end)
        )                                                                as first_name_hash,
        coalesce(
            max(case when a.source_system = 'shopify' then a.last_name_hash end),
            max(case when a.source_system = 'klaviyo' then a.last_name_hash end)
        )                                                                as last_name_hash,

        -- Customer attributes: Shopify wins
        max(case when a.source_system = 'shopify' then a.customer_status   end) as customer_status,
        coalesce(boolor_agg(case when a.source_system = 'shopify' then a.is_b2b_customer end), false) as is_b2b_customer,
        max(case when a.source_system = 'shopify' then a.country_code      end) as country_code,
        max(case when a.source_system = 'shopify' then a.province_code     end) as province_code,
        max(case when a.source_system = 'shopify' then a.postal_code_hash  end) as postal_code_hash,
        max(case when a.source_system = 'shopify' then a.company           end) as company,
        max(case when a.source_system = 'shopify' then a.customer_tags_raw end) as customer_tags_raw,

        -- Consent: Klaviyo wins, fallback to Shopify
        coalesce(
            boolor_agg(case when a.source_system = 'klaviyo' then a.email_subscribed  end),
            boolor_agg(case when a.source_system = 'shopify' then a.email_subscribed  end),
            false
        )                                                                as email_subscribed,
        coalesce(
            boolor_agg(case when a.source_system = 'klaviyo' then a.sms_subscribed    end),
            boolor_agg(case when a.source_system = 'shopify' then a.sms_subscribed    end),
            false
        )                                                                as sms_subscribed,
        coalesce(
            boolor_agg(case when a.source_system = 'klaviyo' then a.marketing_consent end),
            boolor_agg(case when a.source_system = 'shopify' then a.marketing_consent end),
            false
        )                                                                as marketing_consent,

        -- Source systems array
        array_agg(distinct a.source_system)                              as source_systems,

        -- Resolution method: best tier wins
        case
            when boolor_agg(a.identity_resolution_method = 'email')              then 'email'
            when boolor_agg(a.identity_resolution_method = 'phone')              then 'phone'
            when boolor_agg(a.identity_resolution_method = 'fuzzy_name_address') then 'fuzzy_name_address'
            else 'unmatched'
        end                                                              as identity_resolution_method,
        case
            when boolor_agg(a.identity_resolution_method in ('email', 'phone'))  then 'high'
            else 'medium'
        end                                                              as match_confidence,

        min(a.created_at)       as created_at,
        max(a.updated_at)       as updated_at,
        min(a.created_at)::date as acquisition_date
    from all_assigned a
    group by a.customer_id
)

select
    r.customer_id,
    r.shopify_customer_id,
    r.stripe_customer_id,
    r.klaviyo_profile_id,
    r.email_hash,
    r.phone_hash,
    r.first_name_hash,
    r.last_name_hash,
    r.customer_status,
    r.is_b2b_customer,
    r.country_code,
    r.province_code,
    r.postal_code_hash,
    r.company,
    r.customer_tags_raw,
    r.email_subscribed,
    r.sms_subscribed,
    r.marketing_consent,
    r.source_systems,
    r.identity_resolution_method,
    r.match_confidence,
    acq.acquisition_source_system,
    r.acquisition_date,
    r.created_at,
    r.updated_at
from resolved r
left join acquisition acq on r.customer_id = acq.customer_id
