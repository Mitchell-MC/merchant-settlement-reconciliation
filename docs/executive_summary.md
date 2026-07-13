# Executive Summary

**Merchant Settlement Reconciliation & Cash Visibility Platform**
Built for: Meridian Pay (fictional SMB payment facilitator) · Portfolio project, 2026

## The problem

A payment facilitator owes thousands of merchants money every day. The bank doesn't always pay out exactly what the ledger expects, exactly when expected. Without automated reconciliation, breaks are found days late by spreadsheet, triaged inconsistently, and their true cost — capital tied up, funding-line draws — is invisible until it's a crisis. Meridian Pay had no proactive break detection, no aging model, and no auditable trail from a reported number back to source data.

## What was built

A production-styled batch reconciliation platform on Databricks/Unity Catalog:

- **A reconciliation engine** that matches expected settlement to actual bank cash using a documented, configurable date-window and amount-tolerance policy — not ad hoc spreadsheet logic.
- **A synthetic operational dataset** (300 merchants, 6 months, ~1M transactions) with segmentation weights derived from real Census County Business Patterns data, and 6 deliberately injected break patterns used to validate the engine's accuracy end-to-end.
- **A tested medallion lakehouse** (Bronze → Silver → Gold) with 93+ passing data-quality tests, including custom finance-grade assertions (control totals, tolerance-invariant checks, aging SLA breach triggers) — not just generic null checks.
- **A governed access model**: 4 RBAC tiers enforced with real Unity Catalog grants, a pseudonymized view for wide BI audiences, and a documented lineage/glossary trail.
- **Infrastructure as code**: the entire Databricks surface (catalog, schemas, warehouse, RBAC groups, grants, the daily job) is Terraform-managed and reproducible.
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

## What's next (roadmap, if this were a real deployment)

1. Real bank file formats (BAI2/NACHA) instead of a synthetic bank-movement feed.
2. A full classic Databricks workspace inside Meridian Pay's own AWS VPC (cross-account IAM, dedicated storage) — the current Express/serverless workspace was the right choice for a portfolio build, not for a regulated production deployment.
3. Automated break-resolution suggestions using historical root-cause patterns (the `root_cause_hint` field already captures the signal this would train on).
4. Multi-currency support.
5. Real distinct human identities in the RBAC groups via SSO/SCIM (currently structurally correct but unpopulated — see [rbac_access_matrix.md](rbac_access_matrix.md)).

See [charter/PROJECT_CHARTER.md](../charter/PROJECT_CHARTER.md) for the full business framing.
