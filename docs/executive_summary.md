# Executive Summary

**Merchant Settlement Reconciliation & Cash Visibility Platform**
Built for: Meridian Pay (fictional SMB payment facilitator) · Portfolio project, 2026

## The problem

A payment facilitator owes thousands of merchants money every day. The bank doesn't always pay out exactly what the ledger expects, exactly when expected. Without automated reconciliation, breaks are found days late by spreadsheet, triaged inconsistently, and their true cost — capital tied up, funding-line draws — is invisible until it's a crisis. Meridian Pay had no proactive break detection, no aging model, and no auditable trail from a reported number back to source data.

## What was built

A production-styled batch reconciliation platform on Snowflake:

- **A reconciliation engine** that matches expected settlement to actual bank cash using a documented, configurable date-window and amount-tolerance policy — not ad hoc spreadsheet logic.
- **A synthetic operational dataset** (300 merchants, 6 months, ~1M transactions) with segmentation weights derived from real Census County Business Patterns data, and 6 deliberately injected break patterns used to validate the engine's accuracy end-to-end.
- **A tested medallion lakehouse** (Bronze → Silver → Gold) with 93+ passing data-quality tests, including custom finance-grade assertions (control totals, tolerance-invariant checks, aging SLA breach triggers) — not just generic null checks.
- **A governed access model**: 4 RBAC tiers enforced with real Snowflake account-role grants, a pseudonymized view for wide BI audiences, and a documented lineage/glossary trail.
- **Infrastructure as code**: the entire Snowflake surface (database, schemas, warehouses, account roles, grants, service user, Bronze landing stage) is Terraform-managed and reproducible.
- **A CI/CD pipeline** enforcing infra validation → transformation tests → a deliberate, human-approved schedule-activation step.
- **An executive dashboard** with live Gold-layer data: cash position trends, break aging, cash-at-risk by segment, and a merchant-level drill-down.

## What it proves

Every dollar in the Gold layer traces exactly back to Bronze — verified live, not asserted (`$27,806,946.36` in expected settlement volume ties across all three layers with zero drift). The reconciliation engine was validated against ground truth: it correctly classifies clean matches, duplicate postings, and missing postings at >99.8% accuracy, and its two documented failure modes (a small false-break rate on split postings, and correctly rejecting delays that exceed the tolerance policy) are understood, not swept under the rug.

## Production-readiness outcomes

| Control | Status |
|---|---|
| Data quality gates block bad data from reaching Gold | ✅ 93+ dbt tests, 5 custom reconciliation assertions |
| RBAC enforced at the data layer, not just the BI layer | ✅ 4 groups, real `GRANT`s, verified with `SHOW GRANTS` |
| Infrastructure reproducible from code | ✅ `terraform plan` converges to zero drift |
| Deployment order enforced (infra → transform → schedule) | ✅ `.github/workflows/cd.yml`, gated by GitHub Environment approval |
| Incident response documented | ✅ [release_runbook.md](release_runbook.md): rollback, backfill, pause procedures |
| Audit trail from report to source | ✅ [kpi_traceability.md](kpi_traceability.md), lineage columns on every Bronze row |

## Why the design choices were made

**Batch, not streaming.** Settlement reconciles against a bank statement that posts once a day, so there
is no real-time version of "did the money move" to build toward — streaming would solve a problem that
doesn't exist instead of the one that does. Where it would add real value is upstream: landing bank-
movement events incrementally through the day so the daily run starts from current data instead of
batch-loading at cutoff. That's an ingestion-layer addition; Silver, Gold, and the reconciliation engine
stay as they are, because the authoritative comparison is still only answerable once the statement posts.

**A deterministic synthetic dataset, not a repurposed public transactional dataset.** A public dataset
with payer/payee/amount/status fields reshaped into "transactions" produces a fact table with real-
looking columns but no genuine settlement mechanics behind it. The generator instead injects 6 known
break patterns (split settlements, timing delays, amount mismatches, missing postings, duplicate claims,
near-tolerance edge cases) with ground truth recorded at generation time — which is what makes the
>99.8% classification accuracy figure and the two documented failure modes possible to verify rather
than assert. Public reference data (FRPS, CBP, CPI, FRED) is used for what it's actually suited to instead:
scaling and segmentation realism, not as the transactional fact table itself.

**A Databricks-to-Snowflake platform retarget mid-build**, not a green-field Snowflake build. The
migration surfaced real cross-platform differences worth documenting on their own: no Bronze load
mechanism existed on the Databricks side to redirect (built from nothing), Spark-only SQL that silently
changes meaning on Snowflake (`lateral view explode` → `LATERAL FLATTEN`, business-day math broken
by a different `DAYOFWEEK()` convention), and `CREATE OR REPLACE TABLE/VIEW` silently dropping
grants on rebuild where Unity Catalog would have preserved them. See
[snowflake_migration_plan.md](snowflake_migration_plan.md) for the full account.

## What's next (roadmap, if this were a real deployment)

1. Real bank file formats (BAI2/NACHA) instead of a synthetic bank-movement feed.
2. Network-level isolation (private connectivity, IP allowlisting) and a customer-managed encryption key — the current trial-tier account was the right choice for a portfolio build, not for a regulated production deployment.
3. Automated break-resolution suggestions using historical root-cause patterns (the `root_cause_hint` field already captures the signal this would train on).
4. Multi-currency support.
5. Real distinct human identities in the RBAC roles via SSO/SCIM (currently structurally correct but unpopulated — see [rbac_access_matrix.md](rbac_access_matrix.md)).
6. Business-event alerting on high-value exceptions (a critical-severity row in `fct_exception_queue` posting to a webhook) — additive to the pipeline-failure alerting that already exists (`ALERT_WEBHOOK_URL` in the daily/heartbeat workflows), not a new subsystem.
7. Ticketing-system integration (Jira, ServiceNow) writing back to `fct_exception_queue`'s `triage_status`/`triage_owner`/`triage_notes` columns — the persistence path for an external write already exists and is exercised by the same incremental-merge design an analyst uses today.

See [charter/PROJECT_CHARTER.md](../charter/PROJECT_CHARTER.md) for the full business framing.
