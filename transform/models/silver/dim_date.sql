{{
    config(
        materialized='table'
    )
}}

-- Date spine covering the full generation window plus a lookback/lookahead
-- buffer for date-window matching in the reconciliation engine.
with spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2025-11-01' as date)",
        end_date="cast('2026-09-30' as date)"
    ) }}
),

federal_holidays as (
    -- US Federal Reserve holiday calendar; must match data_generation/calendar_utils.py
    -- exactly, since bank posting dates are generated against that same calendar.
    select cast(holiday_date as date) as holiday_date
    from {{ ref('federal_holidays_seed') }}
),

flagged as (
    select
        cast(date_day as date) as date_day,
        -- dayofweek()'s numbering is adapter-native and NOT compared across
        -- platforms: Databricks/Spark returns 1=Sunday..7=Saturday, Snowflake
        -- returns 0=Sunday..6=Saturday. Only the derived is_weekend/
        -- is_business_day booleans below need to be correct per platform --
        -- nothing downstream reads day_of_week_num's raw value.
        dayofweek(date_day) as day_of_week_num,
        dayname(date_day) as day_name,
        case when dayofweek(date_day) in {{ "(0, 6)" if target.type == "snowflake" else "(1, 7)" }} then true else false end as is_weekend,
        case when h.holiday_date is not null then true else false end as is_federal_holiday,
        case
            when dayofweek(date_day) not in {{ "(0, 6)" if target.type == "snowflake" else "(1, 7)" }} and h.holiday_date is null then true
            else false
        end as is_business_day,
        year(date_day) as year,
        month(date_day) as month,
        quarter(date_day) as quarter
    from spine s
    left join federal_holidays h on s.date_day = h.holiday_date
)

select
    *,
    -- Running count of business days up to and including this date. Two
    -- dates share the same seq only when the later one is a non-business
    -- day immediately following the earlier -- this lets the reconciliation
    -- engine compute "N business days after X" via a seq lookup/join instead
    -- of a slow correlated subquery per settlement batch.
    sum(case when is_business_day then 1 else 0 end) over (
        order by date_day rows between unbounded preceding and current row
    ) as business_day_seq
from flagged
