{{ config(materialized='table') }}

-- Channel reference dimension from seeds/channel_mapping.csv per §4.6.
-- One row per canonical channel. Seed maps raw source values to channels;
-- this model deduplicates to one row per channel_id and adds derived attributes.

with seed as (
    select distinct
        cast(channel_id          as varchar)  as channel_id,
        cast(channel_name        as varchar)  as channel_name,
        cast(channel_category    as varchar)  as channel_category,
        cast(channel_subcategory as varchar)  as channel_subcategory,
        cast(is_paid             as boolean)  as is_paid,
        cast(platform            as varchar)  as platform,
        cast(parent_channel      as varchar)  as parent_channel,
        current_timestamp()                   as _extracted_at
    from {{ ref('channel_mapping') }}
)

select
    {{ generate_dim_sk(['channel_id']) }}     as channel_sk,
    channel_id,
    channel_name,
    channel_category,
    channel_subcategory,

    -- channel_type: sales (transactions occur there), acquisition (drives traffic), or both
    case
        when channel_category in ('retail', 'marketplace')
            then 'sales'
        when channel_category in ('search', 'social', 'email', 'direct', 'referral', 'other')
            then 'acquisition'
        else 'both'
    end                                       as channel_type,

    platform,
    parent_channel,
    is_paid,

    -- owned media: email lists and owned online store
    channel_category in ('email', 'online_store')  as is_owned,

    true                                      as is_active,
    current_timestamp()                       as created_at,
    {{ add_audit_columns(
        source_system='seeds',
        source_id_column='channel_id',
        business_columns=['channel_id', 'channel_category'],
        extracted_at_column='_extracted_at'
    ) }}
from seed
