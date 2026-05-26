{% macro lineage_edges() %}
    {#--
        Generates a flat table of model lineage edges from the dbt DAG and
        writes it to <target_database>.metadata.lineage_edges.

        Each row is one directed edge: upstream_model → downstream_model.
        Edge types: 'ref' (model-to-model), 'source' (source-to-model).

        Designed to run as an on-run-end hook. The hook in dbt_project.yml
        is commented out — uncomment once Phase 1 models are materialized.

        Clients can query the resulting table:
            select * from analytics_retail.metadata.lineage_edges
            where downstream_model = 'fact_orders';

        Usage (on-run-end hook in dbt_project.yml):
            on-run-end:
              - "{{ lineage_edges() }}"

        Section 4 Part 2 §4.31
    --#}
    {%- if execute -%}
        {%- set rows = [] -%}

        {%- for node_id, node in graph.nodes.items() -%}
            {%- if node.resource_type == 'model' -%}
                {%- for dep_id in node.depends_on.nodes -%}
                    {%- set parts = dep_id.split('.') -%}
                    {%- if parts[0] == 'model' -%}
                        {%- set upstream  = parts[-1] -%}
                        {%- set edge_type = 'ref' -%}
                    {%- elif parts[0] == 'source' -%}
                        {%- set upstream  = parts[-2] ~ '.' ~ parts[-1] -%}
                        {%- set edge_type = 'source' -%}
                    {%- else -%}
                        {%- set upstream  = parts[-1] -%}
                        {%- set edge_type = 'other' -%}
                    {%- endif -%}
                    {%- do rows.append({
                        'upstream':   upstream,
                        'downstream': node.name,
                        'edge_type':  edge_type
                    }) -%}
                {%- endfor -%}
            {%- endif -%}
        {%- endfor -%}

        {%- if rows | length > 0 -%}
            {%- set build_sql -%}
                create or replace table {{ target.database }}.metadata.lineage_edges as
                {% for row in rows %}
                select
                    '{{ row.upstream }}'   as upstream_model,
                    '{{ row.downstream }}' as downstream_model,
                    '{{ row.edge_type }}'  as edge_type,
                    current_timestamp()    as generated_at
                {% if not loop.last %}union all{% endif %}
                {% endfor %}
            {%- endset -%}
            {%- do run_query(build_sql) -%}
            {% do log("lineage_edges: wrote " ~ rows | length ~ " edges to metadata.lineage_edges", info=true) %}
        {%- else -%}
            {% do log("lineage_edges: no edges found — no models in graph", info=true) %}
        {%- endif -%}
    {%- endif -%}
{% endmacro %}
