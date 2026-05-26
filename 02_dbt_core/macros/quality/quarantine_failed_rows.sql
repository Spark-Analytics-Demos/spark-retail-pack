{% macro quarantine_failed_rows(model_name, unique_key_column, condition) %}
    {#--
        Post-hook that diverts rows failing a business-rule check into a
        quarantine table for analyst review, rather than halting the pipeline.

        This is opt-in per model. Default behavior is to halt on test failure.
        Use this macro only when: (a) the majority of rows are valid, (b) the
        invalid rows are knowable edge cases, and (c) the downstream consumer
        can tolerate their absence.

        Creates quarantine table on first run:
            <target_database>.<target_schema>_quarantine.quarantine_<model_name>

        The quarantine table matches the source model's schema plus two audit
        columns: _failed_check (the condition that failed) and _quarantined_at.

        Usage in model config block:
            {{ config(
                post_hook="{{ quarantine_failed_rows(
                    'fact_orders', 'order_id', 'net_amount >= 0'
                ) }}"
            ) }}

        Section 4 Part 3 §4.42
    --#}
    {%- if execute -%}
        create table if not exists
            {{ target.database }}.{{ target.schema }}_quarantine.quarantine_{{ model_name }}
        as select * from {{ this }} where false;

        insert into {{ target.database }}.{{ target.schema }}_quarantine.quarantine_{{ model_name }}
        select
            *,
            '{{ condition }}'    as _failed_check,
            current_timestamp()  as _quarantined_at
        from {{ this }}
        where not ({{ condition }})
    {%- endif -%}
{% endmacro %}
