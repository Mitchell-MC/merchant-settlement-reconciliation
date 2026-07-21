# The serverless SQL warehouse used by dbt and the analyst-facing BI tools.
# Imported from the workspace's auto-created "Serverless Starter Warehouse"
# (Express workspace setup creates one by default) -- see infra/README.md
# for the import command and the risk of managing an org's only warehouse
# via Terraform (a careless `terraform destroy` would remove it).

resource "databricks_sql_endpoint" "reconciliation" {
  provider                  = databricks.workspace
  name                      = "Serverless Starter Warehouse"
  cluster_size              = var.warehouse_size
  auto_stop_mins            = var.warehouse_auto_stop_minutes
  enable_serverless_compute = true
  max_num_clusters          = 1

  tags {
    custom_tags {
      key   = "project"
      value = "merchant-reconciliation"
    }
    custom_tags {
      key   = "environment"
      value = var.environment
    }
  }
}
