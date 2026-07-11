# NOT APPLIED. Documents what a prod-style environment's settings would be
# (separate catalog, larger warehouse) -- see infra/README.md for why this
# repo only actually deploys dev: a second real environment means a second
# real Databricks catalog/warehouse footprint, which is out of scope cost/
# complexity for a portfolio project with one live workspace. This file is
# the parameterization artifact the plan calls for; running
# `terraform apply -var-file=environments/prod.tfvars` against this same
# workspace would be safe (different catalog name = fully isolated
# objects) if you did want to stand it up.
environment                = "prod"
catalog_name                = "merchant_recon_project_prod"
warehouse_size              = "Medium"
warehouse_auto_stop_minutes = 10
