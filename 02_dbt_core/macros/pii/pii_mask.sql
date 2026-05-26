{% macro pii_mask(column_expr, method='hash') %}
    {#--
        Masks or hashes a PII column according to the current environment config.

        When pii_masking_enabled = false (dev with synthetic data only), the
        column expression is returned unchanged — no masking is applied.

        Methods:
          'hash'   — SHA-256(lower(trim(value)) || salt). Default. Deterministic,
                     allowing joins on hashed values across tables.
          'null'   — Replaces with SQL NULL. Use when the column is only needed
                     for display and no hash join is required.
          'redact' — Replaces with the literal string '[REDACTED]'. Use for
                     display-only text fields where NULL would be misleading.

        The PII hash salt is read from var('pii_hash_salt'), which pulls from
        env var PII_HASH_SALT. Never hardcode the salt value.

        Usage:
            {{ pii_mask('email') }}                    as email
            {{ pii_mask('email') }}                    as email_hash   -- same output; explicit alias
            {{ pii_mask('first_name', method='null') }} as first_name

        Section 8.5, Section 4 Part 1 §4.15
    --#}
    {%- if var('pii_masking_enabled', true) -%}
        {%- if method == 'hash' -%}
            sha2(
                coalesce(lower(trim(cast({{ column_expr }} as varchar))), '')
                || '{{ var("pii_hash_salt", "") }}',
                256
            )
        {%- elif method == 'null' -%}
            cast(null as varchar)
        {%- elif method == 'redact' -%}
            cast('[REDACTED]' as varchar)
        {%- else -%}
            {{ column_expr }}
        {%- endif -%}
    {%- else -%}
        {{ column_expr }}
    {%- endif -%}
{% endmacro %}
