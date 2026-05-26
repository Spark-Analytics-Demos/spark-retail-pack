{% macro generate_dim_sk(natural_key_columns, valid_from_column=none) %}
    {#--
        Generates a surrogate key for a dimension row.

        For Type 1 dimensions (no history), pass only natural_key_columns.
        For Type 2 (SCD2) dimensions, also pass valid_from_column so that
        each version of the same entity gets a distinct surrogate key.

        Wraps dbt_utils.generate_surrogate_key (MD5 hash of concatenated cols).

        Usage:
            Type 1: {{ generate_dim_sk(['channel_id']) }} as channel_sk
            Type 2: {{ generate_dim_sk(['customer_id'], 'valid_from') }} as customer_sk

        Section 4 Part 1 §4.14
    --#}
    {%- if valid_from_column -%}
        {{ dbt_utils.generate_surrogate_key(natural_key_columns + [valid_from_column]) }}
    {%- else -%}
        {{ dbt_utils.generate_surrogate_key(natural_key_columns) }}
    {%- endif -%}
{% endmacro %}
