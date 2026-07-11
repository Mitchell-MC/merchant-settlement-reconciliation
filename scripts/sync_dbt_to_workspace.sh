#!/usr/bin/env bash
# Syncs transform/ to the Databricks workspace path the scheduled job reads
# from (infra/jobs.tf). Terraform doesn't own this -- it's a file sync, not
# infrastructure -- so it has to run manually or from CD (see
# .github/workflows/cd.yml's dbt-deploy job) before the next scheduled run
# picks up any code change.
set -euo pipefail
cd "$(dirname "$0")/.."
databricks sync --full transform /Shared/merchant_reconciliation/transform --profile meridian-dev
