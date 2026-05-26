{% snapshot snap_customer %}

{{
    config(
        target_schema='snapshots',
        strategy='check',
        unique_key='customer_id',
        check_cols=[
            'email_hash',
            'phone_hash',
            'customer_status',
            'country_code',
            'marketing_consent',
            'email_subscribed',
            'sms_subscribed',
            'is_b2b_customer'
        ],
        invalidate_hard_deletes=False
    )
}}

select * from {{ ref('int_customer_identity_resolution') }}

{% endsnapshot %}
