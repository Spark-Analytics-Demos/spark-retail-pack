{{ config(materialized='table') }}

-- Calendar dimension covering 2015-01-01 through 2031-12-31 per §4.5.
-- Relative flags (is_today, is_mtd, etc.) recompute on every build.
-- Fiscal calendar driven by var('fiscal_year_start_month', 1).
-- Holidays joined from ref('holidays') for var('holiday_country_code', 'US').

with date_spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2015-01-01' as date)",
        end_date="cast('2031-12-31' as date)"
    ) }}
),

holidays as (
    select
        cast(date as date) as holiday_date,
        holiday_name
    from {{ ref('holidays') }}
    where country_code = '{{ var("holiday_country_code", "US") }}'
),

spine as (
    select
        cast(d.date_day as date)                                            as date_actual,
        h.holiday_name,
        current_timestamp()                                                 as _extracted_at
    from date_spine d
    left join holidays h on cast(d.date_day as date) = h.holiday_date
),

enriched as (
    select
        -- surrogate key
        year(date_actual) * 10000
            + month(date_actual) * 100
            + day(date_actual)                                              as date_sk,

        date_actual,

        -- day
        dayofweekiso(date_actual)                                           as day_of_week,
        dayname(date_actual)                                                as day_name,
        left(dayname(date_actual), 3)                                       as day_short_name,
        day(date_actual)                                                    as day_of_month,
        dayofyear(date_actual)                                              as day_of_year,
        dayofweekiso(date_actual) >= 6                                      as is_weekend,
        dayofweekiso(date_actual) <= 5                                      as is_weekday,
        (holiday_name is not null)                                          as is_holiday,
        holiday_name,
        (dayofweekiso(date_actual) <= 5 and holiday_name is null)           as is_business_day,

        -- week (ISO: starts Monday)
        weekiso(date_actual)                                                as week_of_year,
        date_trunc('week', date_actual)::date                               as week_starting_date,
        dateadd('day', 6, date_trunc('week', date_actual))::date            as week_ending_date,

        -- month
        month(date_actual)                                                  as month_number,
        monthname(date_actual)                                              as month_name,
        left(monthname(date_actual), 3)                                     as month_short_name,
        date_trunc('month', date_actual)::date                              as month_starting_date,
        last_day(date_actual, 'month')                                      as month_ending_date,

        -- quarter
        quarter(date_actual)                                                as quarter_number,
        'Q' || cast(quarter(date_actual) as varchar)                        as quarter_name,

        -- year
        year(date_actual)                                                   as year,

        -- fiscal calendar (var fiscal_year_start_month: 1 = calendar year)
        case
            when {{ var('fiscal_year_start_month', 1) }} = 1
                then year(date_actual)
            when month(date_actual) >= {{ var('fiscal_year_start_month', 1) }}
                then year(date_actual) + 1
            else year(date_actual)
        end                                                                 as fiscal_year,

        mod(
            month(date_actual) - {{ var('fiscal_year_start_month', 1) }} + 12,
            12
        ) + 1                                                               as fiscal_month,

        ceil((
            mod(
                month(date_actual) - {{ var('fiscal_year_start_month', 1) }} + 12,
                12
            ) + 1
        ) / 3.0)::integer                                                   as fiscal_quarter,

        -- prior year same day
        year(dateadd('year', -1, date_actual)) * 10000
            + month(dateadd('year', -1, date_actual)) * 100
            + day(dateadd('year', -1, date_actual))                         as prior_year_date_sk,
        dateadd('year', -1, date_actual)::date                              as prior_year_date_actual,

        -- relative flags (recomputed each build; negative = past, positive = future)
        datediff('day', current_date(), date_actual)                        as days_from_today,
        date_actual = current_date()                                        as is_today,
        date_actual = dateadd('day', -1, current_date())                    as is_yesterday,
        date_trunc('week', date_actual)::date
            = date_trunc('week', current_date())::date                      as is_current_week,
        date_trunc('month', date_actual)::date
            = date_trunc('month', current_date())::date                     as is_current_month,
        date_trunc('quarter', date_actual)::date
            = date_trunc('quarter', current_date())::date                   as is_current_quarter,
        year(date_actual) = year(current_date())                            as is_current_year,

        -- fiscal year current flag
        (case
            when {{ var('fiscal_year_start_month', 1) }} = 1
                then year(date_actual) = year(current_date())
            when month(date_actual) >= {{ var('fiscal_year_start_month', 1) }}
                then year(date_actual) + 1 = (
                    case
                        when month(current_date()) >= {{ var('fiscal_year_start_month', 1) }}
                            then year(current_date()) + 1
                        else year(current_date())
                    end
                )
            else year(date_actual) = (
                case
                    when month(current_date()) >= {{ var('fiscal_year_start_month', 1) }}
                        then year(current_date()) + 1
                    else year(current_date())
                end
            )
        end)                                                                as is_current_fiscal_year,

        -- period-to-date
        (date_actual between date_trunc('week', current_date())::date
            and current_date())                                             as is_wtd,
        (date_actual between date_trunc('month', current_date())::date
            and current_date())                                             as is_mtd,
        (date_actual between date_trunc('quarter', current_date())::date
            and current_date())                                             as is_qtd,
        (year(date_actual) = year(current_date())
            and date_actual <= current_date())                              as is_ytd,
        -- fiscal YTD: same fiscal year as today AND on or before today
        (case
            when {{ var('fiscal_year_start_month', 1) }} = 1
                then year(date_actual) = year(current_date())
                    and date_actual <= current_date()
            when month(date_actual) >= {{ var('fiscal_year_start_month', 1) }}
                then year(date_actual) + 1 = (
                        case when month(current_date()) >= {{ var('fiscal_year_start_month', 1) }}
                            then year(current_date()) + 1 else year(current_date()) end
                    ) and date_actual <= current_date()
            else year(date_actual) = (
                    case when month(current_date()) >= {{ var('fiscal_year_start_month', 1) }}
                        then year(current_date()) + 1 else year(current_date()) end
                ) and date_actual <= current_date()
        end)                                                                as is_fytd,

        -- trailing windows
        date_actual between dateadd('day', -6,  current_date())
            and current_date()                                              as is_last_7_days,
        date_actual between dateadd('day', -29, current_date())
            and current_date()                                              as is_last_30_days,
        date_actual between dateadd('day', -89, current_date())
            and current_date()                                              as is_last_90_days,
        date_actual between dateadd('day', -364, current_date())
            and current_date()                                              as is_last_365_days,

        _extracted_at
    from spine
)

select
    date_sk,
    date_actual,
    day_of_week,
    day_name,
    day_short_name,
    day_of_month,
    day_of_year,
    is_weekend,
    is_weekday,
    is_holiday,
    holiday_name,
    is_business_day,
    week_of_year,
    week_starting_date,
    week_ending_date,
    month_number,
    month_name,
    month_short_name,
    month_starting_date,
    month_ending_date,
    quarter_number,
    quarter_name,
    year,
    fiscal_year,
    fiscal_month,
    fiscal_quarter,
    prior_year_date_sk,
    prior_year_date_actual,
    days_from_today,
    is_today,
    is_yesterday,
    is_current_week,
    is_current_month,
    is_current_quarter,
    is_current_year,
    is_current_fiscal_year,
    is_wtd,
    is_mtd,
    is_qtd,
    is_ytd,
    is_fytd,
    is_last_7_days,
    is_last_30_days,
    is_last_90_days,
    is_last_365_days,
    {{ add_audit_columns(
        source_system='generated',
        source_id_column='date_sk',
        business_columns=['date_sk'],
        extracted_at_column='_extracted_at'
    ) }}
from enriched
