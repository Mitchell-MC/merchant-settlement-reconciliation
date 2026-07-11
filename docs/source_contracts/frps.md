# Source Contract — FRPS (Federal Reserve Payments Study)

## Purpose
Authoritative macro benchmark for noncash payment volume/value trends (card, ACH, check). Used to sanity-check that synthetic transaction mix (card vs. ACH share, average ticket size) is directionally realistic, and as a scenario-scaling input — not as operational data.

## Access
- **Most recent release:** 2025 triennial study, initial top-line findings published 2026-07-01, covering CY2015–CY2024 (detail years 2015, 2018, 2021, 2024).
- **Download:** Excel workbook — https://www.federalreserve.gov/publications/images/FRPS_CY2024_IDR_data.xlsx
- **Landing page:** https://www.federalreserve.gov/paymentsystems/frps_cy2015_24_topline.htm
- **Archive (prior cycles):** https://www.federalreserve.gov/paymentsystems/frps_previous.htm

## Grain
One row per (`payment_type`, `collection_year`) — a triennial snapshot, not a continuous time series. `payment_type` values: general-purpose card, private-label card, ACH credit, ACH debit, check (interbank), check (on-us), check-converted-to-ACH, ATM cash withdrawal.

## Key fields
| Field | Description |
|---|---|
| `payment_type` | Category of noncash payment |
| `collection_year` | Year the volume/value figure represents (2015, 2018, 2021, 2024, ...) |
| `count_billions` | Number of payments, in billions |
| `value_trillions_usd` | Total value, in trillions USD |
| `avg_transaction_amount` | `value / count`, derived |
| `cagr_pct` | Compound annual growth rate vs. prior snapshot |

## Cadence
Triennial (every 3 years: 2016, 2019, 2022, 2025 cycles), with annual supplements in intervening years. Initial top-line findings lag the final collection year by ~1.5–2 years; detailed tables follow later still. **This is a slowly-changing benchmark dimension, not a daily feed.**

## Null policy
Some `payment_type` breakdowns don't exist in earlier vintages (e.g., private-label card detail only appears from certain years onward) — this is intentional sparsity in the source, not a data quality defect. Do not impute; carry nulls through and document per-vintage coverage in the Silver model.

## Lineage metadata
`source_url`, `publication_date`, `collection_year`, `ingestion_timestamp` on every landed row.

## Late data handling
No SLA in the traditional sense — refresh is a manually-triggered event whenever the Fed publishes a new cycle (check `frps_previous.htm` for new releases). Staleness beyond one full triennial cycle (~3 years past the current snapshot's collection year) triggers a freshness **warning**, not a failure, per [non_functional_targets.md](../non_functional_targets.md).
