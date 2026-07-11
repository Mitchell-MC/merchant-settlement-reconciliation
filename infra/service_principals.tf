# CI/CD identity: GitHub Actions authenticates as this service principal
# (OAuth M2M, client_id/secret) rather than a human's interactive OAuth
# session -- see .github/workflows/ and infra/README.md for the secret
# handoff process (never generated or seen by this Terraform config).

resource "databricks_service_principal" "ci_cd" {
  provider      = databricks.account
  display_name  = "recon-ci-cd"
  application_id = "3acbec4b-0afd-4c00-b39d-3399d8f1d50f"
}

resource "databricks_group_member" "ci_cd_engineering" {
  provider  = databricks.account
  group_id  = databricks_group.engineering.id
  member_id = databricks_service_principal.ci_cd.id
}
