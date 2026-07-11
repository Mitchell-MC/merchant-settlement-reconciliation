# Interview Prep

Grounded in what actually happened building this, not a rehearsed narrative. See [charter/PROJECT_CHARTER.md](../charter/PROJECT_CHARTER.md) for the 2-minute and 5-minute scripted versions — this doc is the deeper material behind them, organized for Q&A rather than a pitch.

## Problem framing

"Anyone who processes third-party payouts — payment facilitators, marketplaces, gig platforms — has to answer one question every day: did the money that was supposed to move actually move, and if not, how much is at risk? I built the platform that answers that question end-to-end: business framing, a reconciliation engine, data quality gates, governance, IaC, CI/CD, and a live executive dashboard — against a real Databricks workspace, not a local mock."

Why this problem, specifically: it's the natural complement to my other portfolio project (real-time fraud/AML streaming). Together they show I understand *when* batch is architecturally correct (settlement reconciles against a bank statement that posts once a day — there's no "real-time" version of that) versus when streaming is (fraud scoring needs sub-second decisions). Picking the right architecture for the problem, not defaulting to one pattern everywhere, is the actual point of having two projects instead of one bigger one.

## Design tradeoffs (the ones worth defending)

**Amount-and-date-window tolerance matching, not exact match.** Exact match sounds cleaner but produces false breaks from routine timing noise (weekend ACH lag, bank cutoffs) — that noise would bury the real breaks. The tolerance policy (floor $1 or 0.1%, whichever's greater; 2-business-day window) is a documented, versioned config value (`dim_finance_assumptions_seed.csv` / dbt vars), not a magic number buried in a query — Treasury can change it without an engineering code review.

**A two-pass greedy matching algorithm, not a full assignment-problem solver.** Pass 1: mutual-nearest-neighbor single-posting match. Pass 2: sum-of-unclaimed-postings for split-posting batches. This is a deliberate scope cut, not an oversight — a real assignment-problem solver (Hungarian algorithm or similar) would handle contested postings optimally, but greedy-with-documented-limitations gets ~99.8% accuracy on 5 of 6 break types and is far simpler to reason about and audit. I know exactly where it's weaker (split postings with overlapping merchant windows, ~81.5% match rate) because I validated against ground truth rather than assuming it worked.

**Full-refresh Gold tables, not incremental.** Every `dbt build` fully rebuilds Silver/Gold. Simpler mental model (every run is a complete, self-consistent snapshot — no partial-state bugs), and cheap enough at this data volume (the whole pipeline runs in under 2 minutes) that incremental complexity isn't worth it yet. Documented as the reason rollback is simple: revert the code, rerun, done — no compensating transactions needed.

**CBP-derived segment weights, with two documented judgment calls, not raw pass-through.** Real Census establishment-count data drives the synthetic merchant industry/region/size mix — but raw whole-economy weights would make "other" (manufacturing, wholesale, utilities) the largest segment, which isn't realistic for a payment facilitator's actual addressable market. I capped it at 5% and rescaled the 7 target industries' *relative* proportions (which is where the real CBP signal has value) to fill the rest. That's a business judgment layered on real data, and I can defend exactly why.

## Production-readiness outcomes — proof, not claims

- **93+ passing dbt tests**, including 5 custom finance-grade assertions beyond generic null/unique checks: a Bronze-vs-Silver control total, a tolerance-invariant sanity check on the engine's own output, a break-rate ceiling (`WARN`), an aging SLA breach trigger (`WARN`), and a posting-claim exclusivity integrity check.
- **RBAC verified with `SHOW GRANTS`**, not just written and assumed correct — and adopting Terraform's authoritative `databricks_grants` resource silently *fixed* a real gap (an auto-created default group with blanket catalog access) as a side effect of `terraform apply`.
- **`terraform plan` converges to zero drift** against the live workspace — imported 17 manually-bootstrapped resources into state, a realistic "IaC adopted after the fact" sequence, not a green-field apply.
- **The scheduled job was actually run, not just defined.** First run failed (`UC_HIVE_METASTORE_DISABLED_EXCEPTION` — the dbt task didn't declare a catalog and fell back to the legacy Hive Metastore). Diagnosed from the real error output, fixed, reran, confirmed `SUCCESS`, cross-checked against `ops.dbt_run_telemetry`.
- **Control totals proven live**: $27,806,946.36 in expected settlement ties exactly across Bronze, Silver, and Gold — see [kpi_traceability.md](kpi_traceability.md).

## Bugs found and fixed during the build (strong material — shows real engineering, not tutorial-following)

1. **Double-counted cash in the reconciliation engine.** The split-posting match pass computed candidates independently per batch; two batches for the same merchant with overlapping reconciliation windows could both claim the same leftover bank postings — meaning the same real dollar was being counted as satisfying two separate settlement obligations. Caught by a new integrity test I wrote (`assert_no_double_claimed_bank_postings`), not by inspection. Fixed with a deterministic tiebreak (earliest `batch_date` wins a contested posting).
2. **A near-miss that would have destroyed the catalog.** The first `terraform plan` after importing the catalog showed `storage_root` forcing full replacement — Terraform saw an unset value in config against a real metastore-assigned value and planned to destroy-and-recreate the catalog (dropping every schema and table under it) to "fix" the diff. Caught by reading `plan` output before applying, which is the entire point of the two-step `plan`/`apply` workflow. Fixed with a documented `lifecycle.ignore_changes` block.
3. **A silent 50-second performance bug.** The lineage row-hash used `.astype(str).agg("|".join, axis=1)` — a row-wise pandas operation that's fine at 10K rows and catastrophic at 1M (50+ seconds per table). Switched to `pandas.util.hash_pandas_object` (vectorized), ~1 second.
4. **Nanosecond timestamps Databricks can't read.** pandas' default `datetime64[ns]` parquet output fails Databricks' reader with `PARQUET_TYPE_ILLEGAL` — Spark timestamps are microsecond precision. Cast explicitly before writing.
5. **Unity Catalog `GRANT` silently rejecting a valid-looking group.** Workspace-scoped SCIM groups (`databricks groups create`) are invisible to Unity Catalog, which only recognizes account-level principals — `GRANT` failed with `PRINCIPAL_DOES_NOT_EXIST` even though `databricks groups list` showed the group existed. Required a second CLI profile authenticated at the account level.

## Next-step roadmap

See [executive_summary.md](executive_summary.md)'s roadmap section — real bank file formats (BAI2/NACHA), a full classic AWS-VPC workspace for a regulated production deployment, ML-assisted break-resolution suggestions (the `root_cause_hint` field is already the training signal), multi-currency, and real SSO/SCIM-provisioned humans in the RBAC groups.

## Anticipated hard questions

**"Why not just use Power BI like the plan said?"** I did document a full Power BI semantic model and DAX measures ([bi/power_bi_connection_guide.md](../bi/power_bi_connection_guide.md)) — but Power BI Desktop wasn't available in the build environment, so I couldn't actually connect and verify it. Rather than ship an unverified `.pbix` and claim it works, I built a real, live-data-driven executive dashboard I could actually test end-to-end, and kept the Power BI artifact honestly labeled as "documented, not built." I'd rather show you one thing that definitely works than two things I'm not sure about.

**"Isn't a synthetic dataset kind of a cop-out?"** The operational data is synthetic by necessity (no real processor/bank feeds are available or appropriate for a portfolio project), but it's not arbitrary — segment weights come from real Census data, the break patterns are injected with known ground truth specifically so the reconciliation engine's accuracy could be *measured*, not assumed. A demo dataset you can't validate against is worse than no demo at all.

**"What would break first at real scale?"** The full-refresh Gold rebuild strategy — fine at ~1M rows/2 minutes, but wouldn't hold at real processor volume (potentially billions of transactions/day). That's the first thing I'd redesign: incremental Silver/Gold models keyed on `batch_date`, and Bronze tables partitioned for true incremental backfill instead of the current full-table-replace approach (documented as a known limitation in [release_runbook.md](release_runbook.md)'s backfill procedure).
