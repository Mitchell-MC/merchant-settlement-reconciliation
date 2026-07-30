# KPI Traceability — Audit Confidence

This is proof, not a promise. **Snowflake is the live platform** (Databricks was retired 2026-07-25 — see [snowflake_migration_plan.md](snowflake_migration_plan.md)); the control totals below were captured while Databricks was still primary and are kept as the original proof this traceability pattern works, not as current numbers. The dbt test that continuously re-verifies this comparison (`transform/tests/assert_bronze_silver_settlement_control_total.sql`) now runs against Snowflake on every `dbt build` — see "Reproducing this yourself" below for the current command.

```sql
SELECT
  (SELECT ROUND(SUM(expected_settlement_amount),2) FROM merchant_recon_project.bronze.settlement_batches) AS bronze_total,
  (SELECT ROUND(SUM(expected_settlement_amount),2) FROM merchant_recon_project.silver.fct_settlement_batch) AS silver_total,
  (SELECT ROUND(SUM(total_expected_settlement_amount),2) FROM merchant_recon_project.gold.fct_daily_cash_position) AS gold_total;
```

| bronze_total | silver_total | gold_total |
|---|---|---|
| 27,806,946.36 | 27,806,946.36 | 27,806,946.36 |

Exact match across all three layers — no silent row loss, no double-counting, no unexplained rounding drift, for the full $27.8M of settlement volume in the demo window. This isn't a one-off spot check either: `transform/tests/assert_bronze_silver_settlement_control_total.sql` runs this exact comparison (Bronze vs. Silver) as a dbt test on every `dbt build`, so it's continuously verified, not just verified once for this document.

## Why this is possible to prove at all

1. **Silver is a thin, typed passthrough.** Every Silver `fct_*`/`dim_*` model is a `SELECT ... CAST ... FROM {{ source(...) }}` with no joins, no aggregation, no business logic (see any file in `transform/models/silver/fct_*.sql`). A number can't silently change shape between Bronze and Silver because nothing in that layer is allowed to change it.
2. **All business logic lives in exactly one place.** The reconciliation engine (`transform/models/silver/int_reconciliation_matches.sql`) is the only model that joins settlement batches to bank postings. Every Gold mart downstream reads from that single engine output — there's one matching result, not five slightly-different ones computed independently per mart.
3. **Lineage columns survive the whole trip.** `_source_system`, `_ingestion_timestamp`, `_batch_id`, `_row_hash` are set once at Bronze landing (`common/lineage.py`) and are queryable on every Bronze row — see [data_governance.md](data_governance.md) for the full manual trace path from a Gold number back to the exact generator/ingestion run that produced it.

## Per-KPI trace map

| Gold KPI | Formula source | Traces through |
|---|---|---|
| Expected Settlement Amount | [kpi_contract.md #1](kpi_contract.md#1-expected-settlement-amount) | `gold.fct_daily_cash_position` ← `silver.int_reconciliation_matches` ← `silver.fct_settlement_batch` ← `bronze.settlement_batches` |
| Actual Cash Received | [kpi_contract.md #2](kpi_contract.md#2-actual-cash-received) | `gold.fct_daily_cash_position` ← `silver.int_reconciliation_matches` ← `silver.fct_bank_movement` ← `bronze.bank_movements` |
| Unresolved Break Amount | [kpi_contract.md #3](kpi_contract.md#3-unresolved-break-amount) | `gold.fct_reconciliation_breaks` ← `silver.int_reconciliation_matches` (both sides above) |
| Break Rate | [kpi_contract.md #4](kpi_contract.md#4-break-rate) | `gold.fct_daily_cash_position`, computed from the same two sums above — never a separately-sourced number |
| Break Aging | [kpi_contract.md #5](kpi_contract.md#5-break-aging) | `gold.fct_reconciliation_breaks` ← `silver.dim_date.business_day_seq` |
| Cash-at-Risk | [kpi_contract.md #6](kpi_contract.md#6-cash-at-risk) | `gold.fct_reconciliation_breaks` ← `seeds/dim_finance_assumptions_seed.csv` (threshold) |
| Funding Cost Estimate | [kpi_contract.md #7](kpi_contract.md#7-funding-cost-estimate) | `gold.fct_reconciliation_breaks` ← `seeds/dim_finance_assumptions_seed.csv` (cost-of-funds rate) |
| Reconciliation Match Rate | [kpi_contract.md #8](kpi_contract.md#8-reconciliation-match-rate-straight-through-rate) | `gold.fct_daily_cash_position`, same engine output as everything above |
| Duplicate Posting Exposure | [kpi_contract.md #9](kpi_contract.md#9-duplicate-posting-exposure) | `gold.fct_duplicate_posting_exceptions` ← `silver.fct_duplicate_postings` ← `int_reconciliation_matches` + `silver.fct_bank_movement` |

## Why `fct_duplicate_posting_exceptions` is a separate mart

`gold.fct_duplicate_posting_exceptions` traces through `silver.fct_duplicate_postings` ← `int_reconciliation_matches` + `silver.fct_bank_movement`, not through `fct_exception_queue`. It surfaces bank postings that duplicate an already-claimed posting (same merchant/date/amount, real cash posted twice) — a bank-movement-side anomaly, not a settlement-batch-side break.

It can't be merged into `fct_exception_queue` for a grain reason: that queue's uniqueness contract is `settlement_batch_id`, and a duplicate posting doesn't have one — it duplicates a posting that a real batch already claimed, so there's no batch to key it to. Folding it in would either break that uniqueness test or force a fake batch id onto a row that isn't a batch. Keeping it a separate mart lets each surface keep an honest grain: `fct_exception_queue` is "one row per open settlement-batch break," `fct_duplicate_posting_exceptions` is "one row per unclaimed duplicate posting."

Severity uses the same $5,000 critical threshold as `fct_exception_queue` (`case when amount >= 5000 then 'critical' else 'high'` — see `transform/models/gold/fct_duplicate_posting_exceptions.sql`): a duplicate payout is real cash out the door twice, so it's held to the same dollar bar as a critical break, not a lesser one.

## Reproducing this yourself

On Snowflake, the equivalent control-total query uses the objects under `MERCHANT_RECON_PROJECT_DEV` (see [rbac_access_matrix.md](rbac_access_matrix.md#snowflake-retarget-same-matrix-same-verification-discipline) for the account/role names) with the same three-layer shape as the query above, uppercased per Snowflake's default identifier casing.

From `transform/`: `dbt test --select assert_bronze_silver_settlement_control_total` — this is the authoritative, continuously-run check; it runs on every `dbt build` (see [ci.yml](../.github/workflows/ci.yml) / [cd.yml](../.github/workflows/cd.yml)) rather than needing to be reproduced by hand.
