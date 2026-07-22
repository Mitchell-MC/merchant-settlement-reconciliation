# Release Checklist, Rollback Playbook, and Backfill Procedure

> **Scope:** this doc covers *planned* changes going wrong — a bad merge, a broken grant, a backfill. For an *unplanned, discovered-late* failure (the pipeline stopped producing correct/current data and nobody caught it), start with [docs/incident_runbook.md](incident_runbook.md) — scope the blast radius and contain first, then come back here for the rollback/backfill mechanics.

## Release checklist

Before merging to `main`:

- [ ] `dbt build` passes locally (`cd transform && dbt build`) — all tests green or only expected `WARN`s (e.g. `assert_aging_sla_breach_trigger` warning on a static historical dataset is expected, not a regression)
- [ ] `terraform plan -var-file=environments/dev.tfvars` in `infra/` shows only the intended diff — no surprise `force replacement`s (see the `storage_root` incident in [infra/README.md](../infra/README.md) for why this matters)
- [ ] If a KPI formula changed: [docs/kpi_contract.md](kpi_contract.md) updated in the same PR (see that doc's cross-cutting rules)
- [ ] If a new Gold table/column is merchant-identifiable: [docs/rbac_access_matrix.md](rbac_access_matrix.md) updated, and a grant added in `infra/grants.tf` for the roles that should see it

After merge (CD pipeline, see `.github/workflows/cd.yml`):

- [ ] `terraform-apply` job succeeded
- [ ] `dbt-deploy` job succeeded (project synced to `/Shared/merchant_reconciliation/transform`, smoke-test `dbt build` passed against the live warehouse)
- [ ] `activate-schedule` approved by a reviewer on the `release` GitHub Environment — this is the deliberate, separate step that actually turns on the daily job; a green CD run through `dbt-deploy` does **not** by itself change what's scheduled to run tomorrow

## Rollback playbook

**If a bad model/test change reaches `main` before the daily job runs:**
1. Pause the job immediately: `databricks jobs update 376440490795606 --json '{"new_settings":{"schedule":{"quartz_cron_expression":"0 0 6 * * ?","timezone_id":"America/New_York","pause_status":"PAUSED"}}}'` — stops the bad code from ever executing on schedule. (JOB_ID is positional in the current CLI; the schedule object is replaced wholesale, so include cron/timezone, not just `pause_status`.)
2. `git revert` the bad commit on `main`, open a PR, let CI re-validate.
3. Re-run `cd.yml` (or push the revert) to re-sync the corrected project and re-approve `activate-schedule`.

**If a bad run already published to Gold:**
1. Gold tables are `materialized='table'` (full rebuild each run, not incremental) — the fix is to revert the code and re-run `dbt build`, which fully replaces the bad Gold tables in place. There's no partial-state cleanup needed because there's no partial state; each run is a complete, self-consistent snapshot.
2. Because every Gold row carries lineage back to a specific `_batch_id` (see [docs/data_governance.md](data_governance.md)), and `ops.dbt_run_telemetry` logs every run's outcome, you can confirm exactly which run produced the bad numbers and for how long they were live before the next successful run overwrote them — useful for any downstream reporting that needs a correction note.
3. If Bronze data itself was bad (not just a transformation bug), see the backfill procedure below instead — reverting the dbt code isn't enough.

**If Terraform apply broke something (e.g. a bad grant change locked out a role):**
1. `terraform plan` immediately to see the exact diff that just applied.
2. If it's a grants regression, the fastest fix is usually re-applying the previous commit's `infra/grants.tf` (`git revert` + `terraform apply`), not a manual `GRANT` — a manual grant will just get reverted by the next `apply` anyway (`databricks_grants` is authoritative, see [infra/README.md](../infra/README.md)).
3. Never `terraform apply` a fix without reading `plan` output first — that's exactly how the `storage_root` incident was caught instead of becoming a real outage.

## Controlled backfill procedure

Use when Bronze data for a past date needs to be regenerated or re-ingested (e.g. a bug in `data_generation/` produced bad synthetic data for a date range, or a macro source needs a corrected historical pull):

1. **Scope the backfill.** Identify the exact date range and which Bronze tables are affected. Bronze is append-only/immutable by policy (see [docs/non_functional_targets.md](non_functional_targets.md)) — a backfill lands *new* corrected rows with a new `_batch_id`, it does not edit existing Bronze rows in place.
2. **Regenerate/re-ingest.** For synthetic data: `python data_generation/generate.py --seed <same seed> ...` reproduces byte-identical output for unaffected dates (determinism is the whole point — see the generator's seed contract), so a targeted fix only changes what actually needed to change. For macro sources: re-run the relevant `ingestion/*_ingest.py` script.
3. **Land and verify Bronze.** Upload to the UC volume and `CREATE OR REPLACE TABLE ... AS SELECT * FROM read_files(...)` as usual (see the Bronze-loading commands in project history) — this replaces the whole Bronze table, which for our batch/table-per-run model is the correct behavior; a true incremental/partition-level backfill would need Bronze tables partitioned by ingestion date, which is a documented growth path, not implemented here (this project's Bronze tables are full-refresh, not append/merge, per the size of a full generator run being cheap enough that partial backfill isn't worth the added complexity yet).
4. **Rebuild Silver/Gold.** `dbt build --full-refresh` from `transform/` — Silver/Gold are also `materialized='table'`, so this is a full, consistent rebuild, not a patch.
5. **Re-validate against ground truth if synthetic data changed.** Re-run the ground-truth cross-tab validation query (see project history / `docs/` for the pattern) to confirm the reconciliation engine still classifies the corrected data as expected before trusting the new Gold numbers.
6. **Document the correction.** Note the backfill in the PR description: what was wrong, what date range, what changed. There's no separate "backfill log" table in this build — the git history and `ops.dbt_run_telemetry` timestamps together are the audit trail.
