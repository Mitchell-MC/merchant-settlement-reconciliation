# Incident Response Runbook — Silent Pipeline Failure

**Scenario this runbook is for:** the daily reconciliation pipeline stopped producing correct, current Gold data and it was not caught immediately — the classic *"failed silently for N hours"* case. This is distinct from a *deployment* going wrong (a bad merge, a broken grant), which is [docs/release_runbook.md](release_runbook.md). Use this doc when the failure was **discovered late** and the first problem is figuring out how much damage was already done.

The order below is deliberate. You do not start by fixing the pipeline. You start by scoping the damage and stopping the bleeding, because on a reconciliation platform the *stale/wrong numbers already sitting in front of Treasury and Finance* are a bigger problem than the broken job. A pipeline that can fail silently for a day was never fully production-grade — closing that gap is Front 4, not an afterthought.

---

## Front 1 — Blast radius first (scope before you touch anything)

Before diagnosing *why* it broke, establish **what consumed the bad/stale data and what state that leaves them in.** On this platform the served surface is the Gold layer and the masked view; the exposure differs sharply by consumer.

| Gold surface | Who consumes it | Decision it drives | Exposure if stale/wrong for N days |
|---|---|---|---|
| `gold.fct_daily_cash_position` | Treasury (`treasury_viewers`), Exec dashboard | Daily funding / cash-at-risk calls | Funding decisions made on an N-day-old cash picture — real money moved on wrong numbers |
| `gold.fct_reconciliation_breaks` | Recon engineering, Finance (`finance_analysts`) | Which settlements are unmatched and need chasing | Breaks not surfaced → unrecovered cash ages silently past SLA |
| `gold.fct_exception_queue` / `gold.vw_exception_queue_masked` | Ops triage, `bi_consumers` | What gets worked today, by severity/owner | Critical exceptions invisible → SLA breaches, aging cash |
| `gold.fct_merchant_exception_trends` | Finance, analysts | Merchant-level risk/segmentation | Trend lines quietly frozen → wrong risk read |
| `gold.fct_funding_cost_summary` | Treasury, Finance | Cost-of-funds reporting | Misstated funding cost in reporting |
| `bi/executive_dashboard.html` + Power BI model | Executives | Board-level cash & exception KPIs | Leadership reads stale KPIs as current |

**Say this out loud in the first 60 seconds:** *"Before I fix anything, what's downstream and what state is it in right now?"* The answer determines everything else — a 72-hour gap in `fct_daily_cash_position` is a Treasury exposure conversation; a 72-hour gap in `fct_merchant_exception_trends` is a reporting-correction note. Same outage, very different blast radius.

Establish the exact window with the data already in `ops`:
- `ops.pipeline_heartbeat.last_run_completed_at` — when a run last completed at all.
- `ops.dbt_run_telemetry` — every run's node-level outcome; confirms *which* run last succeeded and for how long the bad/absent state was live.
- Every Gold row carries lineage back to a `_batch_id` (see [docs/data_governance.md](data_governance.md)), so "which run produced these numbers, and when did the next good run overwrite them" is answerable, not guessed.

## Front 2 — Triage and containment (stop the bleeding before reconstructing)

Containment comes *before* the fix. The goal is to stop consumers from trusting bad data, not yet to produce good data.

1. **Stop it getting worse.** If a run is actively writing suspect data, pause the daily job immediately (same command as the rollback playbook):
   ```bash
   databricks jobs update --job-id <daily_reconciliation_job_id> \
     --json '{"new_settings": {"schedule": {"pause_status": "PAUSED"}}}'
   ```
   The job id is a Terraform output (`daily_reconciliation_job_id`).
2. **Flag the served surface as unreliable — don't silently leave it up.** The honest move is to make the staleness *visible* to consumers rather than let them keep reading a dashboard that looks fine. Options, cheapest first: post a banner/note on `bi/executive_dashboard.html`, notify the `treasury_viewers` / `finance_analysts` / `bi_consumers` channels that Gold as-of `<date>` is under review, and — if the numbers are actively misleading — restrict the masked view or mark the affected `as_of_date` rows. Because Gold is `materialized='table'` (full snapshot per run, no partial state) the *previous good snapshot* is coherent; the danger is people mistaking a frozen snapshot for a current one.
3. **Decide: kill vs. let finish.** If a run is mid-flight and its inputs are suspect, killing it is usually right — a full-refresh rebuild on the next good inputs is cheap and clean here, so there's little value in letting a bad run complete.

## Front 3 — Stakeholder reality (communicate before you have the full picture)

On a cash-visibility platform the cost of Treasury discovering this through a broken report is far higher than the cost of an early, incomplete update from you. Get ahead of it.

**Send within the first ~15 minutes, before root cause is known:**
> Reconciliation Gold data for `<date range>` is currently **under review** — a data-quality issue may mean the figures published since `<last known-good run>` are stale/incomplete. **What we know:** `<one line>`. **What we don't yet know:** `<one line — e.g. whether cash-position figures are affected>`. **Best current estimate to corrected data:** `<time>`. Treat `fct_daily_cash_position` / the exec dashboard as provisional until the all-clear. Next update by `<time>`.

Escalation matrix (who to pull in, by blast radius):

| Condition | Notify |
|---|---|
| Any Gold staleness/gap detected | Recon engineering on-call (`alert_email_recipients`), data eng lead |
| `fct_daily_cash_position` or cash-at-risk affected | + Treasury (`treasury_viewers` owner) — **same-day**, this moves money |
| Critical exceptions missed past SLA | + Finance / ops lead (`finance_analysts` owner) |
| Merchant-identifiable data possibly exposed/incorrect | + governance owner (see [docs/rbac_access_matrix.md](rbac_access_matrix.md)) |

Communicate on a fixed cadence (e.g. hourly) until resolved, even if the update is "still investigating." Silence during an incident reads as a second failure.

## Front 4 — System verdict (the real fix is that it was silent, not that it broke)

Everything above is reconstruction — and this platform already has the reconstruction machinery: [docs/release_runbook.md](release_runbook.md) covers reverting bad code and rebuilding Gold (`dbt build --full-refresh`, full-snapshot tables, lineage-verified), and the backfill procedure covers correcting bad Bronze. **Follow those to produce good data.** Then re-run the ground-truth cross-tab if synthetic/source data changed, and post the all-clear with a correction note pointing at the exact `_batch_id`s that were bad and the window they were live.

But the postmortem question is not "how do we fix this run." It is: **what assumption about our production readiness did a silent N-hour failure just disprove?** The controls that exist specifically so this class of failure is *loud, not silent*:

- **Dead-man's-switch** — `transform/tests/assert_pipeline_not_silent.sql`, run by `databricks_job.pipeline_heartbeat` on an **independent** 6-hourly schedule (`infra/jobs.tf`). It fails when the last logged run is older than `pipeline_heartbeat_threshold_hours` (26h), i.e. when the pipeline has gone quiet — the one check the daily job structurally cannot perform on itself.
- **Source freshness gate** — the daily job runs `dbt source freshness` *before* build; stale/missing operational Bronze fails the job loudly instead of publishing a green Gold built on old data (`transform/models/bronze/_bronze__sources.yml`).
- **Failure + hang notifications** — the daily job's `on_failure` and `on_duration_warning` (a hung run that never errors) route to `alert_email_recipients` (`infra/jobs.tf`).
- **SLA flags** — `ops.run_summary` surfaces break-rate / critical-exception / last-run-failure flags for the daily standup (`transform/models/ops/run_summary.sql`).

Then ask, honestly, **where else this gap still exists** — the "system verdict" the postmortem is actually for:
- Is the heartbeat itself monitored? It runs inside the same platform it watches (the Databricks workspace, or GitHub Actions + the Snowflake warehouse), so a total outage of that platform silences the watcher too. The stated next step, on **both** targets, is a fully **external** heartbeat (an off-platform cron hitting the SQL API) — documented, not yet built (`infra/jobs.tf` and `.github/workflows/snowflake_heartbeat.yml` headers).
- Which target failed? The controls exist on **both** platforms and must be checked on the one that broke: Databricks via `databricks_job.daily_reconciliation` + `databricks_job.pipeline_heartbeat` (`infra/jobs.tf`); Snowflake via `.github/workflows/snowflake_daily.yml` (freshness gate + timeout + failure alert) + `.github/workflows/snowflake_heartbeat.yml` (independent dead-man's-switch). The same `assert_pipeline_not_silent` test and `ops.pipeline_heartbeat` model back both, so the detection logic is identical across targets.
- Were the alert channels actually populated in the environment that failed, or still empty? A wired-but-empty `alert_email_recipients` (Databricks) or unset `ALERT_WEBHOOK_URL` secret (Snowflake) is a silent failure waiting to happen — GitHub's native workflow-failure email is the only backstop until it's set.

The verdict line to land: *a pipeline that can fail silently was never production-grade — production-grade is when the system notices its own absence and pages someone. These four controls are that noticing; the open items above are where it isn't wired yet.*

---

### One-screen checklist

1. **Scope** — `ops.pipeline_heartbeat` / `ops.dbt_run_telemetry` → which run last succeeded, how long the gap ran, which Gold surfaces + consumers are hit (Front 1 table).
2. **Contain** — pause `daily_reconciliation_job_id`; flag the served Gold/dashboard as provisional; kill an in-flight bad run.
3. **Communicate** — first stakeholder update inside 15 min (what we know / don't / ETA); escalate by blast radius; fixed-cadence updates until all-clear.
4. **Reconstruct** — follow [release_runbook.md](release_runbook.md) rollback/backfill; `dbt build --full-refresh`; re-validate vs. ground truth; post correction note with `_batch_id`s.
5. **Verdict** — confirm the heartbeat/freshness/notification controls would now catch a recurrence; log where the gap still exists (external heartbeat, Snowflake parity, empty recipient lists) as follow-up work.
