{{ config(materialized='ephemeral') }}

-- Cleaned FX rate reference from seeds/fx_rates.csv.
-- Ships with quarterly rates for EUR, GBP, CAD, AUD, KES (2020-2026) and
-- annual rates for NGN, ZAR, INR, BRL, MXN. All rates are X → USD.
--
-- For daily resolution, use the daily_fx_rate() macro, which applies a
-- nearest-prior-date (step-function) lookup against ref('fx_rates') directly.
-- This model exposes the same data as a named DAG node so that downstream
-- models can ref() it for lineage tracking or direct JOIN use.
--
-- USD self-reference (rate = 1.0) is included so that reporting-currency
-- orders need no special-casing in downstream FX joins.

with seed_rates as (
    select
        upper(cast(from_currency as varchar)) as from_currency,
        upper(cast(to_currency   as varchar)) as to_currency,
        cast(rate_date as date)               as rate_date,
        cast(rate as numeric(18, 8))          as rate
    from {{ ref('fx_rates') }}
),

-- Explicit self-reference for reporting currency (no lookup needed when currencies match)
self_reference as (
    select
        cast('{{ var("reporting_currency", "USD") }}' as varchar) as from_currency,
        cast('{{ var("reporting_currency", "USD") }}' as varchar) as to_currency,
        cast('2020-01-01' as date)                                as rate_date,
        cast(1.0 as numeric(18, 8))                               as rate
)

select from_currency, to_currency, rate_date, rate
from seed_rates

union all

-- Include self-reference only if reporting currency isn't already in the seed
select * from self_reference
where (from_currency, to_currency) not in (
    select from_currency, to_currency from seed_rates
)
