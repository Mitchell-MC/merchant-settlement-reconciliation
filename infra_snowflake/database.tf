# Snowflake foundations: database + medallion schemas, mirroring
# infra/catalog.tf's Unity Catalog structure. Named in uppercase
# (Snowflake's idiom for unquoted identifiers -- it folds to uppercase
# regardless, so declaring it that way avoids a cosmetic case diff on
# every `terraform plan`), unlike the lowercase Databricks catalog.
#
# Unlike databricks_catalog, Snowflake databases have no storage_root
# drift gotcha (no equivalent metastore-assigned attribute) -- no
# lifecycle block needed here.

resource "snowflake_database" "this" {
  name    = var.database_name
  comment = "Merchant settlement reconciliation platform -- ${var.environment}"
}

resource "snowflake_schema" "bronze" {
  database = snowflake_database.this.name
  name     = "BRONZE"
  comment  = "Raw landed tables: synthetic operational data generator + FRPS/CBP/CPI ingestion. Immutable, append-only."
}

resource "snowflake_schema" "silver" {
  database = snowflake_database.this.name
  name     = "SILVER"
  comment  = "Conformed entities and the reconciliation matching engine."
}

resource "snowflake_schema" "gold" {
  database = snowflake_database.this.name
  name     = "GOLD"
  comment  = "Business-facing marts: cash position, breaks, exception queue, funding cost."
}

resource "snowflake_schema" "ops" {
  database = snowflake_database.this.name
  name     = "OPS"
  comment  = "Observability: dbt run telemetry, reconciliation run summaries."
}
