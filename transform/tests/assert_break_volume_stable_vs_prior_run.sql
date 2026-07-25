-- Run-over-run regression check: did this build's break population move by
-- more than the tolerated share versus the last build that produced one?
--
-- Every other test in this suite is ABSOLUTE -- it asserts a property of the
-- current output in isolation (not null, unique, within tolerance, sums
-- correctly). None of them can see a change in SCALE. If a tolerance-policy
-- edit took break count from 3,425 to 40,000, every absolute test would still
-- pass and the shift would reach the dashboard unremarked. This is the
-- relative check: compare against production's own previous value, the same
-- role the "test vs prod" comparison plays in a pre-production deploy gate.
--
-- Deliberately severity=warn, not error. Break volume legitimately moves
-- with real business conditions (a bank posting delay on one day genuinely
-- creates breaks), so failing the build on a swing would block deploys for
-- correct data and train people to ignore red -- the exact anti-pattern that
-- makes a test suite worthless. This should prompt a look, not a rollback.
--
-- Threshold is 25%: comfortably wider than the observed run-to-run variance
-- on a deterministic seed (which is 0%), narrow enough to catch a policy or
-- join change that materially reshapes the population.
{{ config(severity='warn', tags=['regression']) }}

-- The CURRENT value is read from the live table, not from telemetry. The
-- on-run-end hook that writes telemetry fires AFTER all models and tests
-- complete (see the header of models/ops/run_summary.sql), so this
-- invocation's own row does not exist yet while this test is running.
-- Reading telemetry for both sides would compare the two PREVIOUS runs and
-- silently never evaluate the build actually under test -- it would pass on
-- a run that doubled the break population, then fire one run late.
with current_run as (
    select count(*) as n from {{ ref('fct_reconciliation_breaks') }}
),

prior_run as (
    select
        rows_affected as n,
        run_started_at
    from {{ source('ops', 'dbt_run_telemetry') }}
    where node_name = 'fct_reconciliation_breaks'
      and node_resource_type = 'model'
      and status = 'success'
      -- rows_affected is null when the model was skipped in a partial or
      -- failed invocation. Those rows carry no volume signal, so they are
      -- excluded rather than read as "zero rows" -- treating a skip as a
      -- 100% drop would make this test fire on every partial run.
      and rows_affected is not null
    order by run_started_at desc
    limit 1
)

select
    p.n as prior_break_count,
    c.n as current_break_count,
    c.n - p.n as delta,
    round(abs(c.n - p.n) / nullif(p.n, 0), 4) as pct_change,
    p.run_started_at as prior_run_at
from current_run c
cross join prior_run p
-- No row when there is no prior run to compare against (first build on a
-- fresh warehouse): the cross join yields nothing and the test passes, which
-- is correct -- absence of history is not a regression.
where abs(c.n - p.n) / nullif(p.n, 0) > 0.25
