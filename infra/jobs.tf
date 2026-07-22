# Daily reconciliation run -- the schedule that makes the SLA in
# docs/non_functional_targets.md real rather than aspirational. Runs
# against the dbt project synced to the workspace at
# /Shared/merchant_reconciliation/transform (see scripts/sync_dbt_to_workspace.sh
# -- run manually or from CI before this job's next scheduled fire, since
# Terraform doesn't own the file sync).

resource "databricks_job" "daily_reconciliation" {
  provider = databricks.workspace
  name     = "merchant-reconciliation-daily-${var.environment}"

  schedule {
    quartz_cron_expression = "0 0 6 * * ?" # 06:00 daily -- an hour of buffer before the 07:00 Gold-publish SLA
    timezone_id            = "America/New_York"
    pause_status           = "PAUSED" # see infra/README.md -- paused by default, activated as a deliberate release step, not on every apply
  }

  environment {
    environment_key = "dbt_env"
    spec {
      environment_version = "1"
      dependencies        = ["dbt-databricks>=1.8,<2.0"]
    }
  }

  task {
    task_key        = "dbt_build"
    environment_key = "dbt_env"

    dbt_task {
      project_directory = "/Shared/merchant_reconciliation/transform"
      # `dbt source freshness` runs BEFORE build as a gate: it checks the
      # operational Bronze tables against the freshness thresholds in
      # models/bronze/_bronze__sources.yml and exits non-zero on an `error`
      # state. That deliberately fails the whole job (tripping on_failure
      # below) rather than letting `dbt build` publish a green, "successful"
      # Gold snapshot built on stale or missing T-1 data -- which is exactly
      # how a pipeline fails silently. Loud-and-stopped beats quiet-and-wrong.
      # (The slowly-changing macro sources are exempted per-table in the yml,
      # so this never false-fires on FRPS/CBP/CPI.)
      commands     = ["dbt deps", "dbt seed", "dbt source freshness", "dbt build --exclude tag:heartbeat"]
      warehouse_id = databricks_sql_endpoint.reconciliation.id
      catalog      = databricks_catalog.this.name
      schema       = "silver" # dbt_project.yml's schema configs override this per-model; this is just the connection default
      source       = "WORKSPACE"
    }

    # No new_cluster/existing_cluster_id: this is an Express/serverless
    # workspace (see charter/PROJECT_CHARTER.md) -- the task runs on
    # serverless job compute via the environment block above, not a
    # provisioned classic cluster.
  }

  tags = {
    project     = "merchant-reconciliation"
    environment = var.environment
  }

  # Turn "silent" into "loud": notify on outright failure AND on a run that
  # overruns its wall-clock ceiling (a hung task that never errors emits no
  # failure event on its own). Recipients come from var.alert_email_recipients
  # -- empty in dev, populated per-env. The list being empty is a deployment
  # choice, not a missing control: the wiring is here and live the moment an
  # address is added, unlike the previous hardcoded [] placeholder.
  email_notifications {
    on_failure                             = var.alert_email_recipients
    on_duration_warning_threshold_exceeded = var.alert_email_recipients
  }

  health {
    rules {
      metric = "RUN_DURATION_SECONDS"
      op     = "GREATER_THAN"
      value  = var.max_run_duration_seconds
    }
  }
}

# Dead-man's-switch (incident-readiness). This job exists to answer the one
# question the daily job structurally CANNOT: "did the daily job run at all?"
# ops.run_summary / ops.dbt_run_telemetry are only written when a run
# happens, so a job that stops firing writes nothing and is invisible to any
# check that lives inside the pipeline. This job runs on its OWN independent
# schedule, executes only the assert_pipeline_not_silent dead-man's-switch
# test (no build), and fails -- tripping its on_failure notification -- when
# the last logged run is older than the heartbeat threshold. A monitor that
# shares a schedule with the thing it monitors is not a monitor.
#
# Limitation, stated honestly (see docs/incident_runbook.md "system verdict"):
# this monitor still runs inside the same Databricks workspace/warehouse it
# watches, so a total workspace outage silences the watcher too. A fully
# external heartbeat (an off-platform cron hitting the SQL API) is the
# documented next step, not implemented here.
resource "databricks_job" "pipeline_heartbeat" {
  provider = databricks.workspace
  name     = "merchant-reconciliation-heartbeat-${var.environment}"

  schedule {
    quartz_cron_expression = "0 0 */6 * * ?" # every 6h, independent of the daily job's 06:00 fire
    timezone_id            = "America/New_York"
    pause_status           = var.heartbeat_pause_status # UNPAUSED in real prod -- a switched-off dead-man's-switch detects nothing
  }

  environment {
    environment_key = "dbt_env"
    spec {
      environment_version = "1"
      dependencies        = ["dbt-databricks>=1.8,<2.0"]
    }
  }

  task {
    task_key        = "heartbeat_check"
    environment_key = "dbt_env"

    dbt_task {
      project_directory = "/Shared/merchant_reconciliation/transform"
      # Only the dead-man's-switch test -- cheap, fast, and independent of
      # whether the daily pipeline is healthy. A non-empty result fails the
      # test -> fails this job -> trips on_failure below.
      commands     = ["dbt deps", "dbt test --select assert_pipeline_not_silent"]
      warehouse_id = databricks_sql_endpoint.reconciliation.id
      catalog      = databricks_catalog.this.name
      schema       = "ops"
      source       = "WORKSPACE"
    }
  }

  email_notifications {
    on_failure = var.alert_email_recipients
  }

  tags = {
    project     = "merchant-reconciliation"
    environment = var.environment
    role        = "observability"
  }
}
