# Source Contract — FRED (Federal Reserve Economic Data)

## Purpose
Monthly benchmark-rate signal for the Gold-layer funding-cost assumption. `docs/kpi_contract.md`'s Funding Cost Estimate KPI uses a configurable `assumed_cost_of_funds_rate` (default 8% annualized, representative of an SMB-lender revolving credit line) — FRED's effective fed funds rate and bank prime loan rate are the standard public benchmarks that assumption is priced off of. Enrichment/context input, not operational data; it does not feed the reconciliation engine itself.

## Access
- **API:** FRED (Federal Reserve Economic Data) REST API — https://fred.stlouisfed.org/docs/api/fred/
- **Endpoint used:** `series/observations` — https://fred.stlouisfed.org/docs/api/fred/series_observations.html
- **Series browser:** https://fred.stlouisfed.org/
- **Registration (required, not optional):** free, instant API key at https://fred.stlouisfed.org/docs/api/api_key.html. Unlike the BLS CPI ingest, FRED has no unauthenticated fallback — every request requires `api_key`. Set `FRED_API_KEY` in the environment before running `fred_ingest.py`.

## Series used
| Series ID | Description |
|---|---|
| `FEDFUNDS` | Effective Federal Funds Rate, monthly, percent — the base policy rate |
| `MPRIME` | Bank Prime Loan Rate, monthly, percent — the standard markup benchmark commercial lenders price revolving credit off of (typically fed funds + ~300bps) |

## Grain
One row per (`series_id`, `observation_date`), monthly.

## Key fields
| Field | Description |
|---|---|
| `series_id` | e.g. `FEDFUNDS` |
| `series_type` | Human-readable series label |
| `observation_date` | First-of-month date FRED assigns the observation to |
| `value` | Rate, percent |

## Null policy
FRED represents a suppressed or not-yet-reported observation as the literal string `"."`. Per the same policy as CPI, that is a missing row, not a zero — `fred_ingest.py` drops it rather than coercing.

## Cadence
Monthly. `FEDFUNDS` and `MPRIME` are typically published within the first few business days of the following month. Revisions are rare for these two series (unlike CPI's seasonally-adjusted annual revision).

## Lineage metadata
`series_id`, `pulled_at`, plus the standard `_row_hash`/`_source_system`/`_ingestion_timestamp`/`_batch_id` columns from `common/lineage.py`.

## Late data handling
If the current month's observation hasn't posted yet, use the last available month. Per [non_functional_targets.md](../non_functional_targets.md)'s freshness policy, treat a rate more than 45 days stale the same as CPI: a non-blocking freshness warning, since this is a funding-cost assumption input, not a reconciliation-blocking field.
