# Non-Functional Targets

These are binding operational contracts, not aspirations. Phase 5 (data quality/observability) and Phase 8 (CI/CD) enforce these programmatically.

## Daily SLA

| Milestone | Target |
|---|---|
| Prior business day's Bronze source data landed | By 04:00 local time |
| Silver conformed models refreshed | By 05:30 local time |
| Gold marts (reconciliation, cash position, breaks) published | By 07:00 local time |
| BI dashboards reflect new data | By 07:15 local time |

If the 07:00 Gold publish SLA is missed, the run is flagged `SLA_BREACH` in telemetry and the prior day's Gold snapshot remains the served version (no partial/inconsistent publish — see [[kpi-contract]] point-in-time correctness rule).

## Freshness window

- **Synthetic operational data (transactions, settlements, bank postings):** generated and landed in Bronze for `batch_date = T-1` by the start of the daily run.
- **FRPS:** refreshed on publication (triennial) — treated as a slowly-changing benchmark dimension, not a daily feed. Staleness is expected and documented, not an error.
- **CBP:** refreshed annually on Census release — same slowly-changing treatment as FRPS.
- **CPI:** refreshed monthly, expected lag of ~2 weeks after month-end (matches BLS release cadence). A CPI value more than 45 days stale triggers a freshness warning (not a hard failure — macro enrichment shouldn't block operational reconciliation).

## Reconciliation tolerance policy

A settlement batch is considered **matched** (not a break) if, within the date window below, a bank posting exists such that:

```
ABS(expected_settlement_amount - actual_cash_received) <= GREATEST(1.00, 0.001 * expected_settlement_amount)
```

- **Amount tolerance:** the greater of **$1.00** (absolute floor, handles rounding) or **0.1%** of expected settlement (handles proportional fee/FX noise).
- **Date-window tolerance:** a bank posting dated within **+2 business days** of the settlement batch date is eligible to match. Postings outside this window do not auto-match even if the amount matches exactly (flagged for manual review — could be a coincidental amount match on the wrong batch).
- Any batch with no eligible match within the date window, or a match outside amount tolerance, becomes a **break** as of the date the window closes.
- Tolerance parameters live in a single config table (`dim_finance_assumptions`), not hardcoded in transformation SQL, so Treasury can request a policy change without an engineering code review of business logic.

## Auditability expectations

- **Immutable Bronze:** raw landed records are never updated or deleted; corrections arrive as new events (append-only).
- **Lineage keys on every row:** `source_system`, `ingestion_timestamp`, `batch_id`, `row_hash` carried from Bronze through Silver to Gold.
- **Traceability:** every Gold KPI number must be traceable back to the specific Silver rows and Bronze source records that produced it (enforced via a documented lineage/glossary page in Phase 6, validated in Phase 9 BI packaging).
- **Retention:** 7 years for financial/audit-relevant tables, matching standard financial recordkeeping expectations (this is a portfolio project, so retention is *documented as policy*, not literally enforced for 7 years in a demo environment).
- **Point-in-time correctness:** historical KPI values (e.g., "what was cash-at-risk on March 3rd") must be reproducible from the Gold layer's `run_id`/`as_of_date` partitioning even after underlying breaks later resolve.
