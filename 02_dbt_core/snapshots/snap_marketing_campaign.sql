{% snapshot snap_marketing_campaign %}

{{
    config(
        target_schema='snapshots',
        strategy='timestamp',
        unique_key='campaign_id',
        updated_at='updated_at',
        invalidate_hard_deletes=False
    )
}}

select * from {{ ref('stg_meta_ads__campaigns') }}

{% endsnapshot %}
