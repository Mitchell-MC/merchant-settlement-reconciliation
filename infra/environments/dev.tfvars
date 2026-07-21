environment                 = "dev"
catalog_name                = "merchant_recon_project"
warehouse_size              = "Small"
warehouse_auto_stop_minutes = 10

# Alerting is wired but inert in dev: no real on-call list, and the daily job
# is paused here, so the heartbeat is paused too (an unpaused watcher with
# nothing to watch is just noise). See infra/variables.tf for the rationale
# and environments/prod.tfvars for what a live deployment sets.
alert_email_recipients   = []
max_run_duration_seconds = 3600
heartbeat_pause_status   = "PAUSED"
