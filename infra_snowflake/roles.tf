# RBAC roles -- Snowflake equivalent of infra/groups.tf's four
# account-level Databricks groups. Unlike Unity Catalog, Snowflake roles
# are a single account-wide construct (no workspace-vs-account split),
# so there's only one provider config and one set of role resources.
# (`snowflake_account_role` distinguishes these account-wide roles from
# the newer, narrower `snowflake_database_role` -- not needed here.)
#
# Each custom role is granted to SYSADMIN so it stays visible/manageable
# through the standard role hierarchy rather than being an orphaned role
# only ACCOUNTADMIN can see -- idiomatic Snowflake practice, not a
# Databricks-parity requirement.

resource "snowflake_account_role" "engineering" {
  name    = "RECON_ENGINEERING"
  comment = "Full access to the reconciliation database -- see docs/rbac_access_matrix.md."
}

resource "snowflake_account_role" "treasury_viewers" {
  name    = "RECON_TREASURY_VIEWERS"
  comment = "Read-only access to cash position and funding cost marts."
}

resource "snowflake_account_role" "finance_analysts" {
  name    = "RECON_FINANCE_ANALYSTS"
  comment = "Read access to Silver and Gold for analysis and reporting."
}

resource "snowflake_account_role" "bi_consumers" {
  name    = "RECON_BI_CONSUMERS"
  comment = "BI-tool access to Gold marts, including the masked exception queue view."
}

resource "snowflake_grant_account_role" "engineering_to_sysadmin" {
  role_name        = snowflake_account_role.engineering.name
  parent_role_name = "SYSADMIN"
}

resource "snowflake_grant_account_role" "treasury_viewers_to_sysadmin" {
  role_name        = snowflake_account_role.treasury_viewers.name
  parent_role_name = "SYSADMIN"
}

resource "snowflake_grant_account_role" "finance_analysts_to_sysadmin" {
  role_name        = snowflake_account_role.finance_analysts.name
  parent_role_name = "SYSADMIN"
}

resource "snowflake_grant_account_role" "bi_consumers_to_sysadmin" {
  role_name        = snowflake_account_role.bi_consumers.name
  parent_role_name = "SYSADMIN"
}

# Admin user also gets the engineering role directly, so day-to-day
# dbt/Terraform work can run under least-privilege instead of always
# reaching for ACCOUNTADMIN.
resource "snowflake_grant_account_role" "engineering_to_admin_user" {
  role_name = snowflake_account_role.engineering.name
  user_name = var.snowflake_admin_user
}
