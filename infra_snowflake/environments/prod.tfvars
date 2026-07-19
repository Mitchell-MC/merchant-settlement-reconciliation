# NOT APPLIED. Documents what a prod-style environment's settings would
# be (separate database name, larger warehouses) -- same posture as
# infra/environments/prod.tfvars: a portfolio project with one live
# Snowflake account, so a second real environment is out of scope cost/
# complexity.
#
# DO NOT run `terraform apply -var-file=environments/prod.tfvars` against
# this directory as-is -- it shares dev's Terraform state (see
# infra_snowflake/README.md), so applying this var-file replaces
# (destroys + recreates) the already-applied dev database/schemas
# instead of provisioning a parallel environment, identical to the
# documented near-miss in infra/environments/prod.tfvars. Always read
# `terraform plan -var-file=environments/prod.tfvars` for "forces
# replacement" before ever considering `apply`.
environment                    = "prod"
database_name                  = "MERCHANT_RECON_PROJECT_PROD"
transform_warehouse_size       = "SMALL"
bi_warehouse_size              = "SMALL"
warehouse_auto_suspend_seconds = 600
