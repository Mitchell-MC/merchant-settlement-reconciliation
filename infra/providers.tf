# Two provider configs against the same Databricks OAuth identity, at two
# different API scopes: workspace-level (catalogs/schemas/volumes/warehouses/
# grants live here) and account-level (groups are an account-level construct
# in Unity Catalog -- see docs/rbac_access_matrix.md for why workspace-local
# SCIM groups didn't work for UC grants). Both read credentials from the
# already-authenticated CLI profiles in ~/.databrickscfg -- no secrets here.

provider "databricks" {
  alias   = "workspace"
  profile = "meridian-dev"
}

provider "databricks" {
  alias      = "account"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
  profile    = "meridian-account"
}
