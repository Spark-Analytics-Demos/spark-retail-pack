{% macro customer_erasure() %}
    {#--
        Applies GDPR Article 17 / CCPA erasure requests recorded in
        seeds/erasure_requests.csv.

        Erasure scopes:
          'full_erasure'   — Nulls all PII fields (email, phone, name, city)
                             across dim_customer. The customer row and their
                             order history are RETAINED for analytical integrity;
                             only their identity is destroyed.
          'marketing_only' — Sets marketing_consent, email_subscribed, and
                             sms_subscribed to false. No PII fields are altered.

        Both scopes log to metadata.erasure_log (not yet implemented; Phase 2).

        Designed to run as an on-run-end hook after core models build.
        The hook in dbt_project.yml is commented out — uncomment once
        dim_customer is materialized in Phase 1.

        Caller requires RETAIL_ADMIN role. Never run in dev environments
        against real PII (dev uses synthetic data only).

        Usage (on-run-end hook in dbt_project.yml):
            on-run-end:
              - "{{ customer_erasure() }}"

        Section 4 Part 3 §4.41
    --#}
    {%- if execute -%}
        {%- set erase_pii -%}
            update {{ ref('dim_customer') }}
            set
                email      = null,
                phone      = null,
                first_name = null,
                last_name  = null,
                city       = null
            where customer_id in (
                select customer_id
                from {{ ref('erasure_requests') }}
                where scope = 'full_erasure'
            )
        {%- endset -%}
        {%- do run_query(erase_pii) -%}

        {%- set revoke_consent -%}
            update {{ ref('dim_customer') }}
            set
                marketing_consent = false,
                email_subscribed  = false,
                sms_subscribed    = false
            where customer_id in (
                select customer_id
                from {{ ref('erasure_requests') }}
                where scope in ('full_erasure', 'marketing_only')
            )
        {%- endset -%}
        {%- do run_query(revoke_consent) -%}

        {% do log("customer_erasure: processed requests from erasure_requests seed", info=true) %}
    {%- endif -%}
{% endmacro %}
