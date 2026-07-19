# Single provider, authenticated as the account owner's own user
# (MITCHELLMC) via key-pair auth (RSA_PUBLIC_KEY registered on the user,
# private key never committed to this repo -- see infra_snowflake/README.md).
# ACCOUNTADMIN is used directly for bootstrap, same simplification the
# Databricks stack makes with the developer's own OAuth session in
# infra/providers.tf -- a real enterprise setup would scope a dedicated
# Terraform role instead, but that's out of scope for a single-workspace
# portfolio project.
provider "snowflake" {
  organization_name = var.snowflake_organization_name
  account_name       = var.snowflake_account_name
  user               = var.snowflake_admin_user
  authenticator      = "SNOWFLAKE_JWT"
  private_key        = file(pathexpand(var.snowflake_admin_private_key_path))
  role               = "ACCOUNTADMIN"

  # snowflake_file_format and snowflake_stage are still provider preview
  # resources as of v1.2.x -- both needed for stage.tf's Bronze landing stage.
  preview_features_enabled = ["snowflake_file_format_resource", "snowflake_stage_resource"]
}
