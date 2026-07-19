# Account-wide parameter, not scoped to this project's database: this is
# a brand-new single-purpose Snowflake account, so an account-level
# default carries no risk of colliding with unrelated existing workloads.
#
# Why this exists: Snowflake's CREATE TABLE ... USING TEMPLATE (INFER_SCHEMA)
# -- used by scripts/load_bronze_to_snowflake.py to build Bronze tables
# straight from the Parquet files' own schema -- preserves the Parquet
# column names' exact (lowercase) case as case-sensitive quoted
# identifiers. dbt's generated SQL references columns unquoted (which
# Snowflake case-folds to uppercase), so every dbt source query against
# a Bronze table failed with "invalid identifier" until this was set.
#
# Confirmed by direct testing that this is a session-behavior parameter,
# not a stored table property: setting it only within
# load_bronze_to_snowflake.py's own session had no effect on dbt's
# separate session, even against tables that script had just (re)created.
# It must be set somewhere every future session inherits from -- account
# level is the only option available to both the local dbt CLI and the
# RECON_CI_SVC GitHub Actions session without per-session wiring. Once
# set, it applies immediately to existing tables too (no data/DDL
# recreation needed) -- confirmed against the already-loaded Bronze
# tables before this resource existed.
resource "snowflake_account_parameter" "quoted_identifiers_ignore_case" {
  key   = "QUOTED_IDENTIFIERS_IGNORE_CASE"
  value = "true"
}
