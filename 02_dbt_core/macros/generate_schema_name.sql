{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- elif target.name in ('prod', 'staging') -%}
        {# In prod and staging: use the custom schema name directly (GOLD, MART_SALES, etc.) #}
        {{ custom_schema_name | trim | upper }}
    {%- elif target.name == 'ci' -%}
        {# In CI: prefix with PR number for isolation (ci_42_gold, ci_42_mart_sales) #}
        {{ default_schema }}_{{ custom_schema_name | trim }}
    {%- else -%}
        {# In dev: prefix with developer schema for isolation (dev_denis_gold, dev_denis_mart_sales) #}
        {{ default_schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
