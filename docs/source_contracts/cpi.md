# Source Contract — CPI (Consumer Price Index)

## Purpose
Monthly macro pressure signal for scenario scaling — e.g., stress-testing how inflation-driven transaction-amount growth affects funding cost estimates, or normalizing merchant volume trends against inflation. Enrichment input, not operational data.

## Access
- **API:** BLS Public Data API v2 — https://www.bls.gov/developers/api_signature_v2.htm (JSON; GET for small requests, POST for multi-series/date-range requests)
- **Flat files (alternative):** tab-delimited time-series files under https://download.bls.gov/pub/time.series/cu/ (`cu.data.*` for values, `cu.series` for series metadata)
- **Series lookup UI:** https://data.bls.gov/timeseries/CUUR0000SA0
- **Series ID reference:** https://www.bls.gov/cpi/factsheets/cpi-series-ids.htm
- **Registration (recommended):** free API key at https://data.bls.gov/registrationEngine/ — raises limits from 25→500 daily queries, 25→50 series/request, and unlocks 20-year lookback plus built-in % change calculations.

## Series used
| Series ID | Description |
|---|---|
| `CUUR0000SA0` | CPI-U, US city average, all items, **not seasonally adjusted** — primary series (raw month-over-month reality) |
| `CUSR0000SA0` | Same, **seasonally adjusted** — used for trend analysis, not raw scenario scaling |

## Grain
One row per (`series_id`, `year`, `period`) where `period` is `M01`–`M12` (monthly) or `M13` (annual average).

## Key fields
| Field | Description |
|---|---|
| `series_id` | e.g. `CUUR0000SA0` |
| `year` | Calendar year |
| `period` | Month code (`M01`–`M12`) |
| `value` | Index value |
| `footnote_codes` | BLS footnote flags (e.g., preliminary) |

## Null policy
CPI values are essentially never null once published — a missing (`series_id`, `year`, `period`) row means "not yet released," not "zero." The pipeline must not backfill a missing month with zero or interpolate silently; it should carry the gap forward and flag freshness.

## Cadence
Monthly release, ~2 weeks after month-end (e.g., June CPI released mid-July). Release calendar: https://www.bls.gov/schedule/news_release/cpi.htm. Seasonally-adjusted (SA) series factors are revised annually each February for the prior 5 years — re-pull SA values yearly to capture revisions; NSA values are not revised.

## Lineage metadata
`series_id`, `pull_timestamp`, `api_response_id` (if available), `ingestion_timestamp`.

## Late data handling
If the current month's CPI hasn't been released yet, use the last available month and flag it. Per [non_functional_targets.md](../non_functional_targets.md), a CPI value more than 45 days stale triggers a freshness **warning** (non-blocking — macro enrichment shouldn't halt operational reconciliation).
