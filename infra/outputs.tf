output "catalog_name" {
  value = databricks_catalog.this.name
}

output "warehouse_id" {
  value = databricks_sql_endpoint.reconciliation.id
}

output "warehouse_jdbc_url" {
  value = databricks_sql_endpoint.reconciliation.jdbc_url
}

output "daily_reconciliation_job_id" {
  description = "Job id of the daily reconciliation run -- referenced by the rollback/incident runbooks for pausing."
  value       = databricks_job.daily_reconciliation.id
}

output "pipeline_heartbeat_job_id" {
  description = "Job id of the independent dead-man's-switch job (see docs/incident_runbook.md)."
  value       = databricks_job.pipeline_heartbeat.id
}

output "rbac_group_ids" {
  value = {
    engineering      = databricks_group.engineering.id
    treasury_viewers = databricks_group.treasury_viewers.id
    finance_analysts = databricks_group.finance_analysts.id
    bi_consumers     = databricks_group.bi_consumers.id
  }
}
