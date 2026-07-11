# KPI Traceability — Audit Confidence

This is proof, not a promise: control totals for `expected_settlement_amount` were pulled live from the running Databricks workspace across all three medallion layers.

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

## Reproducing this yourself

```bash
databricks auth login --host https://dbc-08add949-9c19.cloud.databricks.com --profile meridian-dev
databricks api post /api/2.0/sql/statements --json '{"warehouse_id":"59901b31d31db40a","statement":"<the query above>","wait_timeout":"30s"}' --profile meridian-dev
```

Or from `transform/`: `dbt test --select assert_bronze_silver_settlement_control_total`.
