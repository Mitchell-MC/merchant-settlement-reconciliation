-- Dead-man's-switch (incident-readiness): FAILS when the reconciliation
-- pipeline has gone SILENT -- no successful dbt invocation within the
-- expected daily cadence, or the most recent invocation had failing nodes.
-- This is the specific control for the "failed silently for 72 hours"
-- scenario the incident runbook (docs/incident_runbook.md) is built around.
--
-- Unlike every other test in this project, this one is NOT meant to run as
-- part of `dbt build`. Running it inside the daily build is pointless: if
-- the build is executing, the pipeline is by definition not silent. It has
-- to run on its own clock so it still fires when the daily job itself has
-- stopped firing. It is executed by databricks_job.pipeline_heartbeat (see
-- infra/jobs.tf) on an independent 6-hourly schedule; a non-empty result
-- fails the test, fails that job, and trips its on_failure notification.
--
-- It queries the raw ops.dbt_run_telemetry source directly (not the
-- pipeline_heartbeat model) on purpose -- the check must not depend on the
-- heartbeat model having been rebuilt, only on the append-only telemetry
-- log, which is the ground truth for "did a run happen and when".
--
-- Cross-target: this test is shared by the Databricks and Snowflake targets,
-- so the hour delta uses the adapter-dispatched {{ dbt.datediff }} macro
-- rather than a raw timestampdiff() -- per the migration's gotcha #4
-- (docs/snowflake_migration_plan.md), cross-database date math must go
-- through dbt's dispatched macros to compile correctly on both engines.
--
-- Returns rows (= failure) when ANY of:
--   * no run has ever been logged (last_run_completed_at is null), or
--   * the most recent run is older than the heartbeat threshold, or
--   * the most recent run had one or more failing/erroring nodes.
{{ config(
    severity='error',
    tags=['heartbeat', 'incident_readiness']
) }}

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
    {{ dbt.datediff('lr.last_run_completed_at', dbt.current_timestamp(), 'hour') }} as hours_since_last_run,
    {{ var('pipeline_heartbeat_threshold_hours', 26) }} as heartbeat_threshold_hours,
    lrh.last_run_node_failures
from last_run lr
cross join last_run_health lrh
where lr.last_run_completed_at is null
   or {{ dbt.datediff('lr.last_run_completed_at', dbt.current_timestamp(), 'hour') }} > {{ var('pipeline_heartbeat_threshold_hours', 26) }}
   or lrh.last_run_node_failures > 0
