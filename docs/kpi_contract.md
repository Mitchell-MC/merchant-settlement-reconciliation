# KPI Contract

This is the authoritative definition of every business metric this platform publishes. Gold-layer models must implement these formulas exactly; any deviation is a bug, not a design choice. Each KPI below states its **grain**, **formula**, **source fields**, and **owner** (the stakeholder who can change its definition).

Tolerance and SLA parameters referenced here are defined in full in [non_functional_targets.md](non_functional_targets.md).

## 1. Expected Settlement Amount
- **Grain:** one row per (merchant_id, settlement_batch_id, batch_date)
- **Formula:** `gross_transaction_volume - interchange_fees - network_fees - processing_fees - reserve_holds + reserve_releases - returns_and_adjustments`
- **Source:** Silver `settlement_batch` conformed entity, rolled up from Bronze transaction/fee/reserve/return events
- **Owner:** Controller / Accounting

## 2. Actual Cash Received
- **Grain:** one row per (merchant_id, settlement_batch_id, bank_posting_date)
- **Formula:** sum of matched `bank_movement` postings attributable to a settlement batch, within the reconciliation window (see tolerance policy)
- **Source:** Silver `bank_movement` conformed entity, joined to `settlement_batch` via the reconciliation engine's match keys
- **Owner:** Treasury

## 3. Unresolved Break Amount
- **Grain:** one row per (merchant_id, settlement_batch_id) where a break exists as of the report date
- **Formula:** `ABS(expected_settlement_amount - actual_cash_received)` for batches where the difference exceeds the amount-tolerance AND remains unmatched after the date-window has elapsed
- **Source:** Gold `fct_reconciliation_breaks`
- **Owner:** Controller / Accounting

## 4. Break Rate
- **Grain:** one row per (report_date) or (report_date, merchant_segment)
- **Formula (count basis):** `unresolved_break_count / total_settlement_batch_count` for the period
- **Formula (dollar basis):** `unresolved_break_amount / total_expected_settlement_amount` for the period
- Both variants are published; count basis drives operational triage, dollar basis drives financial materiality.
- **Owner:** Head of Merchant Operations

## 5. Break Aging
- **Grain:** one row per (merchant_id, settlement_batch_id, as_of_date) for every open break
- **Formula:** `as_of_date - break_first_identified_date`, bucketed into: `0-1`, `2-3`, `4-7`, `8-14`, `15+` business days
- **Source:** Gold `fct_reconciliation_breaks`, aging computed at each daily run (a break's age grows until it matches or is written off)
- **Owner:** Head of Merchant Operations

## 6. Cash-at-Risk
- **Grain:** one row per (report_date) or (report_date, merchant_segment)
- **Formula:** `SUM(unresolved_break_amount)` for breaks aged beyond the SLA threshold (default: > 5 business days, see non-functional targets)
- **Source:** Gold `fct_reconciliation_breaks` filtered to aging bucket `8-14` and `15+`
- **Owner:** VP Treasury

## 7. Funding Cost Estimate
- **Grain:** one row per (report_date) or (report_date, merchant_segment)
- **Formula:** `SUM(unresolved_break_amount * days_outstanding * assumed_cost_of_funds_rate / 365)`
- `assumed_cost_of_funds_rate` is a configurable parameter (default 8% annualized, representative of an SMB-lender revolving credit line), documented in the Gold model's metadata, not hardcoded inline
- **Source:** Gold `fct_reconciliation_breaks` joined to a `dim_finance_assumptions` config table
- **Owner:** VP Treasury

## 8. Reconciliation Match Rate (straight-through rate)
- **Grain:** one row per (report_date) or (report_date, merchant_segment)
- **Formula:** `auto_matched_expected_settlement_amount / total_expected_settlement_amount`
- This is the operational health metric for the reconciliation engine itself — a falling match rate is an early warning of upstream data quality issues, independent of any single merchant's break.
- **Owner:** Data/Analytics Engineering

## Cross-cutting rules

- All dollar amounts are in USD, stored as `DECIMAL(18,2)`, never floating point.
- "Business day" excludes weekends and the US federal holiday calendar (see `dim_date` in Silver).
- Every Gold KPI row carries `run_id` and `as_of_date` so historical KPI values are reproducible even after a break later resolves (point-in-time correctness — a break's aging as reported on day 5 shouldn't change retroactively).
- KPI definitions are version-controlled here; changing a formula requires updating this file in the same PR as the model change (enforced conceptually in Phase 6 governance, checked in Phase 8 CI).
