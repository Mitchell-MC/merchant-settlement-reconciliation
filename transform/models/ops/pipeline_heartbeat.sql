-- Dead-man's-switch surface (Phase 5 / incident-readiness): a single-row
-- table exposing when the reconciliation pipeline last actually ran, so the
-- "failed silently for 72 hours" failure mode becomes visible instead of
-- silent.
--
-- Why this exists: ops.run_summary and ops.dbt_run_telemetry are only ever
-- written WHEN a run happens. If the scheduled job stops firing entirely
-- (paused by mistake, scheduler misfire, an upstream break that aborts the
-- whole task), no telemetry row is written and nothing notices -- the last
-- known values just quietly age. Detecting that requires a check that runs
-- on its OWN clock, independent of this pipeline, and alerts on the ABSENCE
-- of a recent run. That check is the singular test
-- transform/tests/assert_pipeline_not_silent.sql, executed by the separate,
-- independently-scheduled databricks_job.pipeline_heartbeat (see
-- infra/jobs.tf). This model is the human/BI-facing companion to it.
--
-- IMPORTANT -- staleness is computed at READ time, not build time. This
-- model stores last_run_completed_at; consumers compute age live with
-- timestampdiff(hour, last_run_completed_at, current_timestamp()). If the
-- job dies, this table freezes at its last value and the computed age keeps
-- growing -- which is exactly what lets the age cross the threshold and trip
-- the alert. A precomputed "hours_since_last_run" column would be frozen too
-- and would never grow, so it is deliberately NOT stored here.
--
-- Same one-run-lag caveat as ops.run_summary: the on-run-end telemetry hook
-- (transform/macros/log_run_results.sql) fires AFTER this model builds, so
-- last_run_completed_at reflects the previous completed invocation, not the
-- one currently running. That is at most ~24h inside a 26h threshold, so it
-- does not cause false alerts under normal daily cadence.
{{ config(materialized='table') }}

with last_run as (
    select max(run_started_at) as last_run_completed_at
    from {{ source('ops', 'dbt_run_telemetry') }}
),

last_run_health as (
    select
        coalesce(sum(case when status in ('fail', 'error') then 1 else 0 end), 0) as last_run_node_failures
    from {{ source('ops', 'dbt_run_telemetry') }}
    where invocation_id = (
        select invocation_id
        from {{ source('ops', 'dbt_run_telemetry') }}
        order by run_started_at desc
        limit 1
    )
)

select
    lr.last_run_completed_at,
    lrh.last_run_node_failures,
    {{ var('pipeline_heartbeat_threshold_hours', 26) }} as heartbeat_threshold_hours,
    current_timestamp() as heartbeat_written_at
from last_run lr
cross join last_run_health lrh
