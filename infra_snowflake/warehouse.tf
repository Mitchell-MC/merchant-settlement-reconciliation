# Two warehouses instead of Databricks' single serverless SQL warehouse
# doing both jobs -- separates dbt transform compute from BI/analyst
# query compute so a heavy `dbt build` can't starve a treasury dashboard
# refresh, and so cost is attributable per workload.

resource "snowflake_warehouse" "transform" {
  name           = "TRANSFORM_WH"
  warehouse_size = var.transform_warehouse_size
  auto_suspend   = var.warehouse_auto_suspend_seconds
  auto_resume    = true
  initially_suspended = true
  comment        = "dbt build/seed/deps compute for the daily reconciliation run."
}

resource "snowflake_warehouse" "bi" {
  name           = "BI_WH"
  warehouse_size = var.bi_warehouse_size
  auto_suspend   = var.warehouse_auto_suspend_seconds
  auto_resume    = true
  initially_suspended = true
  comment        = "Power BI / analyst-facing query compute -- kept separate from transform load."
}
