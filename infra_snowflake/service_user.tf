# CI/CD identity: GitHub Actions authenticates as this service user via
# key-pair auth (RSA_PUBLIC_KEY baked in below, private key handed to
# GitHub Actions as a secret -- never generated or seen by this
# Terraform config) rather than a human's interactive session. Mirrors
# infra/service_principals.tf's OAuth M2M service principal.

locals {
  # Snowflake's ALTER/CREATE USER ... RSA_PUBLIC_KEY wants the base64
  # body only, not the PEM header/footer -- strip both and the
  # newlines dbt/Terraform doesn't need.
  ci_cd_public_key = replace(
    replace(
      replace(file(pathexpand(var.ci_cd_public_key_path)), "-----BEGIN PUBLIC KEY-----", ""),
      "-----END PUBLIC KEY-----", ""
    ),
    "\n", ""
  )
}

resource "snowflake_service_user" "ci_cd" {
  name              = "RECON_CI_SVC"
  comment            = "GitHub Actions CI/CD identity for the daily dbt build against Snowflake."
  rsa_public_key     = local.ci_cd_public_key
  default_role       = snowflake_account_role.engineering.name
  default_warehouse  = snowflake_warehouse.transform.name
  default_namespace  = "\"${snowflake_database.this.name}\".\"${snowflake_schema.silver.name}\""
}

resource "snowflake_grant_account_role" "engineering_to_ci_cd" {
  role_name = snowflake_account_role.engineering.name
  user_name = snowflake_service_user.ci_cd.name
}
