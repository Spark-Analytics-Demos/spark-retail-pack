{% macro daily_fx_rate(from_currency_column, date_column) %}
    {#--
        Returns the FX rate from a source currency to the project's reporting
        currency (var.reporting_currency, default 'USD').

        Rate lookup strategy:
          1. Find the most recent rate in seeds/fx_rates.csv where
             rate_date <= the target date (nearest-prior-rate approach).
          2. Fall back to 1.0 when source currency = reporting currency
             (no conversion needed; avoids a seed miss for the common case).
          3. Return NULL when no rate exists for a non-reporting currency.
             Downstream models should treat NULL as a data-quality flag,
             not silently zero-out revenue.

        v1 note: fx_rates seed ships with representative quarterly rates for
        GBP, EUR, CAD, AUD, and KES vs. USD (covering 2020–2026). For
        production multi-currency deployments, replace with a daily FX
        connector (e.g., Fivetran Exchange Rates, Open Exchange Rates) and
        populate seeds/fx_rates.csv with daily rates.

        Usage:
            {{ daily_fx_rate('original_currency_code', 'order_date') }}
                as fx_rate_to_reporting

        Section 4 Part 3 §4.47, Section 4 Part 2 §4.19
    --#}
    {%- set reporting_currency = var('reporting_currency', 'USD') -%}
    coalesce(
        (
            select rate
            from {{ ref('fx_rates') }}
            where from_currency = upper({{ from_currency_column }})
              and to_currency   = '{{ reporting_currency }}'
              and rate_date     <= {{ date_column }}::date
            order by rate_date desc
            limit 1
        ),
        case
            when upper({{ from_currency_column }}) = '{{ reporting_currency }}'
            then 1.0
            else null
        end
    )
{% endmacro %}
