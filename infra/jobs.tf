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
    timezone_id             = "America/New_York"
    pause_status             = "PAUSED" # see infra/README.md -- paused by default, activated as a deliberate release step, not on every apply
  }

  environment {
    environment_key = "dbt_env"
    spec {
      environment_version = "1"
      dependencies         = ["dbt-databricks>=1.8,<2.0"]
    }
  }

  task {
    task_key         = "dbt_build"
    environment_key = "dbt_env"

    dbt_task {
      project_directory = "/Shared/merchant_reconciliation/transform"
      commands           = ["dbt deps", "dbt seed", "dbt build"]
      warehouse_id       = databricks_sql_endpoint.reconciliation.id
      catalog             = databricks_catalog.this.name
      schema              = "silver" # dbt_project.yml's schema configs override this per-model; this is just the connection default
      source              = "WORKSPACE"
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

  email_notifications {
    on_failure = []  # documented placeholder -- see infra/README.md; no real distribution list to notify in this portfolio project
  }
}
