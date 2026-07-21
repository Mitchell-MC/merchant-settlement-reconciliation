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

variable "alert_email_recipients" {
  description = <<-EOT
    Email addresses notified when the daily reconciliation job fails, runs
    too long, or when the independent heartbeat job detects the pipeline has
    gone silent. Empty in dev on purpose -- this is a portfolio project with
    no real on-call distribution list, and an alert nobody receives is just
    noise in the run history. A real deployment populates this per
    environment (see environments/prod.tfvars). Wiring the address list
    through a variable, rather than hardcoding [], is the point: the control
    exists and is one tfvars line away from live.
  EOT
  type        = list(string)
  default     = []
}

variable "max_run_duration_seconds" {
  description = <<-EOT
    Wall-clock ceiling for the daily reconciliation run. A run that exceeds
    this trips the job health rule and an on_duration_warning notification --
    catching the "job is hung, not failed" silent-failure vector (a task that
    neither errors nor finishes emits no failure alert on its own). 3600s =
    1h, comfortably above a normal run against this dataset.
  EOT
  type        = number
  default     = 3600
}

variable "heartbeat_pause_status" {
  description = <<-EOT
    Whether the independent dead-man's-switch job (databricks_job.
    pipeline_heartbeat) is scheduled. PAUSED in dev because the daily job it
    watches is itself paused here (portfolio workspace, not run on a real
    daily cadence) -- an unpaused heartbeat would "fire" every interval with
    nothing to watch. A real prod deployment sets this UNPAUSED: the whole
    value of a dead-man's-switch is that it is always on. This is the one job
    that must NOT default to off in production.
  EOT
  type        = string
  default     = "PAUSED"
  validation {
    condition     = contains(["PAUSED", "UNPAUSED"], var.heartbeat_pause_status)
    error_message = "heartbeat_pause_status must be PAUSED or UNPAUSED."
  }
}
