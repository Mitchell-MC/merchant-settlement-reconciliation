# Infrastructure as Code

Terraform manages the Databricks/Unity Catalog surface for this project against the real, live workspace (`dbc-08add949-9c19.cloud.databricks.com`). Everything in this directory was bootstrapped manually first (via the Databricks CLI, during initial platform build-out) and then **imported** into Terraform state — a realistic sequence, not a green-field `terraform apply`. See git history for the CLI commands that originally created each object.

## What's code-managed vs. manual

| Managed by Terraform | Managed manually / by dbt |
|---|---|
| Catalog (`databricks_catalog`) | Table/view DDL and data (owned by dbt — see `transform/`) |
| Schemas: bronze/silver/gold/ops (`databricks_schema`) | Row data (owned by `data_generation/` and `ingestion/`) |
| Bronze landing volumes (`databricks_volume`) | Databricks account signup, AWS Marketplace subscription (one-time, human, can't be automated — needs email verification) |
| SQL warehouse (`databricks_sql_endpoint`) | OAuth CLI profile authentication (`databricks auth login` — per-developer, not shared state) |
| RBAC groups (`databricks_group`, account-level) | |
| Grants (`databricks_grants`) — catalog/schema/table level | |

This split is deliberate: Terraform owns the *access surface* (what exists, who can touch it), dbt owns the *data* (what's inside it). A `terraform apply` never creates or drops a table — that would fight with `dbt build`'s own DDL management.

## Environments

Only `dev` (`environments/dev.tfvars`) is actually applied — this is a portfolio project with one live workspace. `environments/prod.tfvars` documents what a second environment's settings would be (separate catalog name, larger warehouse) to satisfy the "parameterize dev and prod-style settings" requirement without provisioning real duplicate infrastructure that costs money and isn't needed. Running `terraform apply -var-file=environments/prod.tfvars` against this same workspace would be safe to actually try — the catalog name differs, so it's a fully isolated object, not a collision.

## Drift-check process

```bash
cd infra
terraform init                                    # first time / after provider version changes
terraform plan -var-file=environments/dev.tfvars   # shows drift; should be "No changes" in steady state
```

Run `plan` before any manual change to the workspace (e.g. an ad-hoc `GRANT` someone runs by hand) — it will show up as a diff on the next `plan`, which is the whole point: Terraform state is the source of truth for "what should exist," and drift is visible, not silent.

## A real near-miss, left in as a lesson

The first `terraform plan` against the imported catalog showed `storage_root` **forcing replacement of the entire catalog** — Terraform saw an unset value in config against a real value in the metastore and planned to destroy-and-recreate the catalog (which would have dropped every schema and table under it) to "fix" the diff. Caught by reading the plan output before applying, not by luck. Fixed with a `lifecycle { ignore_changes = [storage_root] }` block on `databricks_catalog.this` (see `catalog.tf`) — `storage_root` is metastore-assigned at creation for a managed catalog and this config never sets it, so Terraform should never try to change it. **Always read `terraform plan` output for "forces replacement" before running `apply`, especially on the first `plan` after an import.**

## Known limitations

- `databricks_grants` is authoritative (overwrites, not additive) per securable — declaring a securable's grants here fully replaces whatever was there before, including anything a human granted by hand out-of-band. This is a feature (drift gets corrected), but it means an emergency manual grant will be silently reverted on the next `apply` unless it's also added to the `.tf` file.
- A full "classic" Databricks workspace deployed inside the user's own AWS VPC (cross-account IAM role, S3 bucket, network config via `databricks_mws_*` account resources + the `aws` provider) is documented as the growth path in [charter/PROJECT_CHARTER.md](../charter/PROJECT_CHARTER.md) but not implemented — this project's workspace is an Express/serverless deployment that Databricks manages the underlying AWS infrastructure for, which doesn't need or expose those resources.
