# Snowflake Migration: What Was Built, What It Found, and the Cutover Checklist

This documents a real, verified retarget of the platform onto Snowflake, run in parallel with the live Databricks build (see [architecture.md](architecture.md)) — not a paper plan. Every claim below was checked against the live Snowflake account `DZVUEJF-DF04786`, not assumed from documentation.

## Target architecture

Snowflake for Bronze/Silver/Gold/Ops (`MERCHANT_RECON_PROJECT_DEV`, four schemas, mirroring the Unity Catalog layout) → dbt Core run from GitHub Actions (`snowflake_daily.yml`, no Databricks-Job equivalent exists in Snowflake Terraform) → Power BI connected directly to Snowflake. Bronze lands through an **internal Snowflake stage**, not S3 — a deliberate simplification from the original sketch (S3 + storage integration), chosen to avoid provisioning new AWS IAM/bucket infrastructure for a single-environment portfolio project. See [infra_snowflake/README.md](../infra_snowflake/README.md) for the full stack.

`infra/` (Databricks) and `infra_snowflake/` (Snowflake) are two fully separate Terraform stacks, no shared state, so a mistake in one can never touch the other.

## What was built

- **`infra_snowflake/`** — database, 4 schemas, 2 warehouses (`TRANSFORM_WH`, `BI_WH`), 4 account roles, the full grants matrix, a service user (`RECON_CI_SVC`) for CI, an internal stage + shared Parquet file format, and an account-wide parameter. Applied against the live account; `terraform plan` converges except one documented cosmetic drift (see the README).
- **`transform/`** — a `snowflake` target added to `profiles.yml`/`profiles.yml.example` alongside the existing Databricks one (both stay selectable via `--target`, needed for the parallel run). Real Spark-only SQL rewritten behind `{% if target.type == 'snowflake' %}` branches: `lateral view explode` → `LATERAL FLATTEN`, `array()`/`collect_list()` → `ARRAY_CONSTRUCT()`/`ARRAY_AGG()`, a 2-argument `datediff()` call moved to the adapter-dispatched `dbt.datediff()` macro, and `dim_date`'s weekend/business-day logic corrected for Snowflake's different `DAYOFWEEK()` numbering (0=Sunday vs. Databricks' 1=Sunday). Two hardcoded `merchant_recon_project` database references (one in a macro, one in a source YAML) parameterized to `{{ target.database }}`.
- **`scripts/load_bronze_to_snowflake.py`** — new (no Databricks equivalent existed to redirect: Bronze table creation/loading there has always been manual/out-of-band). Uses `INFER_SCHEMA` + `CREATE OR REPLACE TABLE ... USING TEMPLATE` to build each Bronze table straight from its Parquet file's own schema, then `COPY INTO`. All 9 declared Bronze tables loaded successfully (`merchants`, `transactions`, `settlement_batches`, `reserve_events`, `returns_adjustments`, `bank_movements`, `frps_payment_volumes`, `cbp_establishments`, `cpi_monthly`).
- **`data_generation/config.py`** — fixed a pre-existing path inconsistency while touching the landing mechanism: `output_dir`/`ground_truth_dir` were CWD-relative (unlike every `ingestion/*.py` script's `PROJECT_ROOT`-anchored path); now anchored the same way.
- **`.github/workflows/snowflake_daily.yml`** + **`.github/ci_snowflake/profiles.yml`** — scheduled dbt run against Snowflake as `RECON_CI_SVC`, gated behind a `SNOWFLAKE_DAILY_ENABLED` repo variable (mirrors `infra/jobs.tf`'s `pause_status = "PAUSED"` — activation is a deliberate step, not automatic). Verified end-to-end locally with the real `RECON_CI_SVC` key: full `dbt build` passes.
- **`docs/rbac_access_matrix.md`, `docs/architecture.md`, `bi/power_bi_connection_guide.md`** — extended (not replaced) with the Snowflake-side role mapping, diagram, and connection instructions.

## Real gotchas this migration surfaced (not in the original plan sketch)

These were found by actually running the migration, not anticipated in advance — worth reading before repeating this on another Snowflake account:

1. **No real Bronze load mechanism existed to redirect.** The Databricks source YAML's `loader: databricks_copy_into` was a free-text doc field; nothing in the repo actually loaded parquet into Unity Catalog. Building `load_bronze_to_snowflake.py` was new work, not a config swap.
2. **`INFER_SCHEMA`-driven table creation preserves Parquet column-name case as case-sensitive quoted identifiers**, but dbt's generated SQL references columns unquoted (case-folded uppercase) — every source test failed with "invalid identifier" until `QUOTED_IDENTIFIERS_IGNORE_CASE` was set. Confirmed by direct testing that this **must be an account-level setting**, not per-session: setting it only within the load script's own session had zero effect on dbt's separate session, even against tables that script had just recreated. See `infra_snowflake/account_parameters.tf`.
3. **Snowflake's default `CREATE OR REPLACE TABLE`/`VIEW` drops existing grants on rebuild** — unlike Unity Catalog, where a dbt-rebuilt table keeps its ACLs. Terraform-applied treasury/bi_consumers grants on the two named Gold tables and the masked view were silently wiped by a later `dbt build`. Fixed with `copy_grants=true` on those three models (Snowflake-only, via the same `target.type` Jinja pattern). Verified by rebuilding twice in a row and re-checking `SHOW GRANTS` after each — see `docs/rbac_access_matrix.md`.
4. **`dbt_utils.datediff` doesn't exist** in current dbt_utils (1.4.1) — cross-database date macros were absorbed into dbt-core itself. The adapter-dispatched macro is `dbt.datediff`, not `dbt_utils.datediff`.
5. **`snowflake_file_format` and `snowflake_stage` are still provider preview resources** (`snowflakedb/snowflake` v1.2.x) requiring `preview_features_enabled` in the provider block.
6. **The provider moved registries**: `Snowflake-Labs/snowflake` → `snowflakedb/snowflake`, with several resources renamed (`snowflake_role` → `snowflake_account_role`, `snowflake_grant_privileges_to_role` → `snowflake_grant_privileges_to_account_role`, etc.) — following older tutorials/docs verbatim will hit `terraform validate` errors immediately.
7. **dbt-snowflake's private key path does not expand `~`** — needs an absolute path (or, for CI, the `private_key` field accepting raw PEM text directly, which sidesteps the issue entirely).

## Verification performed

- `terraform plan` against the live account: clean create, then converges to a single documented cosmetic diff (see `infra_snowflake/README.md`) — no unexpected drift.
- `dbt build --target snowflake`: **93 pass, 1 expected warning (aging SLA breach trigger — same "warn not error" behavior as Databricks, not a regression), 0 errors**, across 2 seeds, 15 table models, 1 view model, 75 data tests.
- Re-ran the same build as the `RECON_CI_SVC` CI identity (not the admin user) with identical results, confirming the GitHub Actions workflow's credentials are sufficient before ever relying on it live.
- `SHOW GRANTS TO ROLE <x>` / `SHOW GRANTS ON <object>` for all 4 roles, cross-checked against the documented matrix, including the grants-wiped-on-rebuild gotcha above.
- Rebuilt the 3 grant-sensitive Gold models twice in a row post-fix to confirm `copy_grants` is stable, not a one-time artifact.

## Parallel-run / cutover checklist

Not yet done — this is the hand-off, deliberately not automated:

- [ ] Run both platforms for several consecutive daily cycles (enable `SNOWFLAKE_DAILY_ENABLED`, keep the Databricks job as-is).
- [ ] Compare Gold outputs by `run_id`/`as_of_date` between platforms using the same methodology as [kpi_traceability.md](kpi_traceability.md).
- [ ] Confirm SLA timing on Snowflake, including the known EST/EDT drift in `snowflake_daily.yml`'s fixed-UTC cron.
- [ ] Confirm RBAC parity holds after a real multi-day run (not just this session's rebuild test) — re-run `SHOW GRANTS` after the first live scheduled run.
- [ ] Connect Power BI to Snowflake using `bi/power_bi_connection_guide.md` and confirm all 7 measures render and RLS restricts the BI-consumer-equivalent role to the masked view only.
- [ ] Only after all of the above: decommission the Databricks Terraform stack (`infra/`) as a **separate, explicitly-confirmed action** — this destroys real provisioned infrastructure and is not part of anything automated here.
