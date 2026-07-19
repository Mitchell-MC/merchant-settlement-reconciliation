variable "snowflake_organization_name" {
  description = "Snowflake organization name (Admin -> Accounts -> Account identifier)."
  type        = string
  default     = "DZVUEJF"
}

variable "snowflake_account_name" {
  description = "Snowflake account name (Admin -> Accounts -> Account identifier)."
  type        = string
  default     = "DF04786"
}

variable "snowflake_admin_user" {
  description = "Bootstrap identity Terraform authenticates as (ACCOUNTADMIN, key-pair auth)."
  type        = string
  default     = "MITCHELLMC"
}

variable "snowflake_admin_private_key_path" {
  description = "Path to the admin user's PKCS8 private key, kept outside the repo (see infra_snowflake/README.md)."
  type        = string
  default     = "~/.snowflake/keys/mitchellmc_rsa_key.p8"
}

variable "ci_cd_public_key_path" {
  description = "Path to the RECON_CI_SVC service user's PEM public key, kept outside the repo."
  type        = string
  default     = "~/.snowflake/keys/recon_ci_svc_rsa_key.pub"
}

variable "environment" {
  description = "dev or prod -- see infra_snowflake/environments/*.tfvars. Only dev is actually applied; prod values are documented, not deployed, same posture as infra/variables.tf."
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "database_name" {
  description = "Snowflake database name for this environment."
  type        = string
  default     = "MERCHANT_RECON_PROJECT_DEV"
}

variable "transform_warehouse_size" {
  description = "Warehouse size for dbt transform compute."
  type        = string
  default     = "XSMALL"
}

variable "bi_warehouse_size" {
  description = "Warehouse size for BI/analyst query compute."
  type        = string
  default     = "XSMALL"
}

variable "warehouse_auto_suspend_seconds" {
  description = "Seconds of inactivity before a warehouse auto-suspends. 600s mirrors infra/variables.tf's 10-minute Databricks auto_stop_mins default."
  type        = number
  default     = 600
}
