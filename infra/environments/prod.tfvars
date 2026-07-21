# NOT APPLIED. Documents what a prod-style environment's settings would be
# (separate catalog, larger warehouse) -- see infra/README.md for why this
# repo only actually deploys dev: a second real environment means a second
# real Databricks catalog/warehouse footprint, which is out of scope cost/
# complexity for a portfolio project with one live workspace. This file is
# the parameterization artifact the plan calls for.
#
# DO NOT run `terraform apply -var-file=environments/prod.tfvars` against
# this directory as-is -- it shares dev's Terraform state, so applying this
# var-file replaces (destroys + recreates) the already-applied dev catalog/
# schemas/volumes instead of provisioning a parallel environment. Verified
# via `terraform plan` on 2026-07-11: 11 resources to destroy, including all
# four schemas and both Bronze volumes. See infra/README.md's "Environments"
# section for what a real fix (separate state per environment) would need.
environment                 = "prod"
catalog_name                = "merchant_recon_project_prod"
warehouse_size              = "Medium"
warehouse_auto_stop_minutes = 10

# In a real prod deployment the alerting controls are live, not inert:
#   * a real on-call distribution list receives failure / hang / silence alerts
#   * the dead-man's-switch is UNPAUSED -- always on is the entire point
# (documented, not applied -- see the header above and infra/README.md).
alert_email_recipients   = ["data-oncall@meridianpay.example"]
max_run_duration_seconds = 3600
heartbeat_pause_status   = "UNPAUSED"
