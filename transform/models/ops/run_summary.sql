-- Observability (Phase 5): one row summarizing the latest reconciliation
-- run's health -- what an on-call engineer or the daily ops standup would
-- actually check first, without hunting through Gold tables.
--
-- Note: telemetry logging happens in an on-run-end hook that fires AFTER
-- all models (including this one) finish, so last_run_at/last_run_test_
-- failures here reflect the *previous* completed invocation, not the one
-- currently running -- there's no way for a model to see its own run's
-- outcome mid-run.
{{ config(materialized='table') }}

with latest_day as (
    select *
    from {{ ref('fct_daily_cash_position') }}
    order by batch_date desc
    limit 1
),

exception_summary as (
    select
        count(*) as open_exception_count,
        sum(case when severity = 'critical' then 1 else 0 end) as critical_count,
        sum(case when severity = 'high' then 1 else 0 end) as high_count,
        sum(break_amount) as total_open_break_amount,
        sum(funding_cost_estimate) as total_funding_cost_estimate
    from {{ ref('fct_exception_queue') }}
),

telemetry_summary as (
    select
        max(run_started_at) as last_run_at,
        sum(case when status in ('fail', 'error') then 1 else 0 end) as last_run_test_failures
    from {{ source('ops', 'dbt_run_telemetry') }}
    where invocation_id = (select invocation_id from {{ source('ops', 'dbt_run_telemetry') }} order by run_started_at desc limit 1)
)

select
    ld.batch_date as latest_report_date,
    ld.settlement_batch_count,
    ld.break_count,
    ld.break_rate_dollar_basis,
    ld.reconciliation_match_rate,
    es.open_exception_count,
    es.critical_count,
    es.high_count,
    es.total_open_break_amount,
    es.total_funding_cost_estimate,
    ts.last_run_at,
    ts.last_run_test_failures,
    -- SLA flags, per docs/non_functional_targets.md
    case when ld.break_rate_dollar_basis > 0.10 then true else false end as sla_flag_break_rate_ceiling_breached,
    case when es.critical_count > 0 then true else false end as sla_flag_critical_exceptions_open,
    case when ts.last_run_test_failures > 0 then true else false end as sla_flag_last_run_had_failures
from latest_day ld
cross join exception_summary es
cross join telemetry_summary ts
