{% macro incremental_lookback(date_column, fact_name=none) %}
    {#--
        Emits the WHERE clause for incremental fact loads using a lookback
        window rather than a strict high-water mark.

        Pure high-water-mark loads miss late-arriving records: a refund
        on Day 8 updates an order from Day 1, but a Day-8-only load won't
        re-scan Day 1's rows. The lookback window re-scans the trailing N
        days from the current max, catching edits and late arrivals within
        the configured window.

        N is resolved in order of specificity:
          1. var('incremental_lookback_<fact_name>_days') — per-fact override
          2. var('incremental_lookback_days', 14)         — project default

        Emits nothing (no WHERE clause) on a full-refresh run so that the
        full history is loaded.

        Default lookback windows by fact (Section 4 Part 3 §4.35):
          fact_orders:              14 days  (refunds, edits within ~2 weeks)
          fact_order_lines:         14 days
          fact_refunds:             30 days  (chargebacks arrive weeks late)
          fact_marketing_spend:      7 days  (platform retroactive adjustments)
          fact_web_sessions:         3 days
          fact_email_engagement:     3 days
          fact_inventory_movements:  7 days

        Usage (in a fact model's select):
            select * from {{ ref('stg_shopify__orders') }}
            {{ incremental_lookback('updated_at', 'fact_orders') }}

        Section 4 Part 3 §4.35
    --#}
    {%- if is_incremental() -%}
        {%- if fact_name -%}
            {%- set per_fact_var = 'incremental_lookback_' ~ fact_name ~ '_days' -%}
            {%- set days = var(per_fact_var, var('incremental_lookback_days', 14)) -%}
        {%- else -%}
            {%- set days = var('incremental_lookback_days', 14) -%}
        {%- endif -%}
        where {{ date_column }} >= (
            select dateadd('day', -{{ days }}, max({{ date_column }}))
            from {{ this }}
        )
    {%- endif -%}
{% endmacro %}
