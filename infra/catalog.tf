# Unity Catalog foundations: catalog, medallion schemas, and the raw
# landing volumes used by data_generation/ and ingestion/. All imported
# from the manually-bootstrapped state (see infra/README.md) -- this file
# is the source of truth going forward, not the CLI commands that created
# them originally.

resource "databricks_catalog" "this" {
  provider = databricks.workspace
  name     = var.catalog_name
  comment  = "Merchant settlement reconciliation platform -- ${var.environment}"

  # storage_root is assigned by the metastore at creation time for a managed
  # catalog and isn't set in this config -- without ignore_changes, Terraform
  # sees "declared: null, actual: s3://..." and plans to force-replace the
  # ENTIRE catalog (destroying every schema/table under it) to "fix" that
  # diff. Confirmed via `terraform plan` before ever applying. Never remove
  # this without first setting storage_root explicitly to the real value.
  lifecycle {
    ignore_changes = [storage_root]
  }
}

resource "databricks_schema" "bronze" {
  provider     = databricks.workspace
  catalog_name = databricks_catalog.this.name
  name         = "bronze"
  comment      = "Raw landed tables: synthetic operational data generator + FRPS/CBP/CPI ingestion. Immutable, append-only."
}

resource "databricks_schema" "silver" {
  provider     = databricks.workspace
  catalog_name = databricks_catalog.this.name
  name         = "silver"
  comment      = "Conformed entities and the reconciliation matching engine."
}

resource "databricks_schema" "gold" {
  provider     = databricks.workspace
  catalog_name = databricks_catalog.this.name
  name         = "gold"
  comment      = "Business-facing marts: cash position, breaks, exception queue, funding cost."
}

resource "databricks_schema" "ops" {
  provider     = databricks.workspace
  catalog_name = databricks_catalog.this.name
  name         = "ops"
  comment      = "Observability: dbt run telemetry, reconciliation run summaries."
}

resource "databricks_volume" "bronze_landing" {
  provider     = databricks.workspace
  catalog_name = databricks_catalog.this.name
  schema_name  = databricks_schema.bronze.name
  name         = "landing"
  volume_type  = "MANAGED"
  comment      = "Raw parquet landing zone for the synthetic generator and macro-source ingestion scripts."
}

resource "databricks_volume" "bronze_qa_fixtures" {
  provider     = databricks.workspace
  catalog_name = databricks_catalog.this.name
  schema_name  = databricks_schema.bronze.name
  name         = "qa_fixtures"
  volume_type  = "MANAGED"
  comment      = "Test fixtures (e.g. generator ground truth) -- never part of the production Bronze DAG."
}
