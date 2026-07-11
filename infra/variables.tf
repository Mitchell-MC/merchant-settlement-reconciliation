variable "databricks_account_id" {
  description = "Databricks account ID (account console -> Settings)."
  type        = string
  default     = "662b79e1-4316-4bf8-9d0b-eb5666ac1d98"
}

variable "environment" {
  description = "dev or prod -- see infra/environments/*.tfvars. Only dev is actually applied; prod values are documented, not deployed (see infra/README.md)."
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "catalog_name" {
  description = "Unity Catalog catalog name for this environment."
  type        = string
  default     = "merchant_recon_project"
}

variable "warehouse_size" {
  description = "SQL warehouse cluster size."
  type        = string
  default     = "Small"
}

variable "warehouse_auto_stop_minutes" {
  description = "Minutes of inactivity before the serverless warehouse auto-suspends."
  type        = number
  default     = 10
}
