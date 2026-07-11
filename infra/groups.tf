# Account-level RBAC groups -- see docs/rbac_access_matrix.md for the full
# role model and rationale. Unity Catalog grants require account-level
# principals, not workspace-local SCIM groups (learned the hard way -- see
# git history / project memory).

resource "databricks_group" "engineering" {
  provider     = databricks.account
  display_name = "recon_engineering"
}

resource "databricks_group" "treasury_viewers" {
  provider     = databricks.account
  display_name = "recon_treasury_viewers"
}

resource "databricks_group" "finance_analysts" {
  provider     = databricks.account
  display_name = "recon_finance_analysts"
}

resource "databricks_group" "bi_consumers" {
  provider     = databricks.account
  display_name = "recon_bi_consumers"
}
