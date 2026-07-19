# Bronze load mechanism, no external S3 bucket: ingestion/data_generation
# scripts PUT local parquet straight into this Snowflake-internal stage
# (see scripts/load_bronze_to_snowflake.py), then COPY INTO loads it into
# the Bronze tables. Deliberately simpler than the S3 + storage-integration
# design the migration plan first sketched -- an internal stage needs no
# new AWS IAM role/bucket policy, appropriate for a single-environment
# portfolio project (same "avoid unneeded cloud footprint" posture as
# infra/README.md's Express/serverless Databricks choice).

resource "snowflake_file_format" "parquet" {
  database    = snowflake_database.this.name
  schema      = snowflake_schema.bronze.name
  name        = "PARQUET_FORMAT"
  format_type = "PARQUET"
  comment     = "Shared Parquet file format for Bronze COPY INTO loads."
}

resource "snowflake_stage" "bronze_landing" {
  database    = snowflake_database.this.name
  schema      = snowflake_schema.bronze.name
  name        = "BRONZE_LANDING"
  # KNOWN NON-CONVERGENT DRIFT (documented, not chased further -- see
  # infra_snowflake/README.md): the provider re-escapes this string's
  # embedded quote characters differently on every state refresh than how
  # the config declares them, so `terraform plan` always shows a cosmetic
  # 1-resource diff here even immediately after a clean apply. An
  # unqualified format name (no embedded quotes) avoids the diff but
  # Snowflake's ALTER STAGE rejects it outright -- confirmed by testing,
  # not assumption. Functionally correct either way (PUT/COPY INTO both
  # work); only `terraform plan`'s output is cosmetically wrong.
  file_format = "FORMAT_NAME = ${snowflake_file_format.parquet.fully_qualified_name}"
  comment     = "Internal landing stage for ingestion/*.py and data_generation/generate.py parquet output."
}
