{% macro apply_source_mapping(source_name, table_name) %}
    {#--
        Returns a dict of { canonical_column: source_column } overrides for
        the given source + table, read from dbt_project.yml vars.

        Clients configure overrides in dbt_project.yml under vars:

            vars:
              source_mapping_overrides:
                shopify__orders:
                  field_mappings:
                    order_id:   custom_order_id     # client renamed this column
                    net_amount: final_charged_amount

        The files in seeds/source_mappings/*.yml are documentation templates
        that show all available mapping keys and their default values.
        They are NOT read at build time by this macro (dbt seeds only process
        CSV files). Treat them as structured documentation for implementers.

        Returns an empty dict when no overrides are configured for the table,
        which causes source_col() to fall back to the default column name.

        Section 6.2 (mapping configuration pattern), Phase 1 ADR decision:
        option (c) — SQL-native macros, YAML files as documentation templates.
    --#}
    {%- set override_key    = source_name ~ '__' ~ table_name -%}
    {%- set all_overrides   = var('source_mapping_overrides', {}) -%}
    {%- set table_overrides = all_overrides.get(override_key, {}) -%}
    {%- set field_mappings  = table_overrides.get('field_mappings', {}) -%}
    {{ return(field_mappings) }}
{% endmacro %}


{% macro source_col(source_name, table_name, canonical_column, default_column) %}
    {#--
        Returns the source column expression to use for a canonical column,
        applying any client-configured field_mapping override.

        Falls back to default_column when no override is configured for
        canonical_column in the given source + table context.

        Usage in a staging model:
            {{ source_col('shopify', 'orders', 'order_id', 'id') }} as order_id

        If a client has overridden order_id → custom_order_id in vars, this
        macro returns 'custom_order_id'. Otherwise returns 'id'.

        Section 6.2
    --#}
    {%- set mappings = apply_source_mapping(source_name, table_name) -%}
    {%- if canonical_column in mappings -%}
        {{ mappings[canonical_column] }}
    {%- else -%}
        {{ default_column }}
    {%- endif -%}
{% endmacro %}
