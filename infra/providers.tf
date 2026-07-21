# Two provider configs against the same Databricks OAuth identity, at two
# different API scopes: workspace-level (catalogs/schemas/volumes/warehouses/
# grants live here) and account-level (groups are an account-level construct
# in Unity Catalog -- see docs/rbac_access_matrix.md for why workspace-local
# SCIM groups didn't work for UC grants).
#
# Dual-mode auth so the SAME config runs locally and in CI:
#   * Local dev: the profile variables default to the meridian-dev / meridian-
#     account CLI profiles in ~/.databrickscfg -- no secrets in the repo.
#   * CI (GitHub Actions): the workflow sets both profile vars to "" (via
#     TF_VAR_*), so the ternaries below resolve to null. A null `profile` is
#     equivalent to omitting the argument, which makes the provider fall back
#     to OAuth M2M from env vars -- DATABRICKS_HOST + DATABRICKS_CLIENT_ID/
#     SECRET for the workspace provider, and the host/account_id below plus the
#     same client creds for the account provider. A hardcoded profile that
#     doesn't exist on the runner is exactly what broke CD's terraform-apply.

provider "databricks" {
  alias   = "workspace"
  profile = var.databricks_workspace_profile != "" ? var.databricks_workspace_profile : null
}

provider "databricks" {
  alias      = "account"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
  profile    = var.databricks_account_profile != "" ? var.databricks_account_profile : null
}
