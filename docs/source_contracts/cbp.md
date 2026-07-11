# Source Contract — CBP (County Business Patterns)

## Purpose
Drives realistic merchant segmentation for the synthetic data generator: geography mix, industry (NAICS) mix, and employer-size-class distribution should reflect real US business population patterns, not a uniform/arbitrary distribution.

## Access
- **Most recent vintage:** 2023 (released 2025-06-26; 2024 vintage due summer 2026).
- **Landing page:** https://www.census.gov/data/datasets/2023/econ/cbp/2023-cbp.html
- **Flat-file downloads (ZIP containing CSV):**
  - County: https://www2.census.gov/programs-surveys/cbp/datasets/2023/cbp23co.zip
  - State: `cbp23st.zip`, US: `cbp23us.zip`, MSA: `cbp23msa.zip`, CSA: `cbp23csa.zip`
  - Index of all files: https://www.census.gov/programs-surveys/cbp/data/datasets.html
- **API (alternative to flat file):** `api.census.gov/data/2023/cbp` — e.g. `?get=ESTAB,LFO,NAICS2017_LABEL,NAME&for=state:06&NAICS2017=72&key=YOUR_KEY`. Docs: https://www.census.gov/data/developers/data-sets/cbp-zbp/cbp-api.html. Requires a free Census API key.
- **Schema reference:** record layouts — https://www.census.gov/programs-surveys/cbp/technical-documentation/record-layouts.html; 2023 User Guide — https://www2.census.gov/programs-surveys/cbp/resources/2023-CBP-User-Guide.pdf

For this project we use the **county-level flat file** (`cbp23co.zip`) — a one-time reference download, not an API integration, since this data refreshes annually and is a dimension enrichment input, not a live feed.

## Grain
One row per (`county` (state+county FIPS), `NAICS industry code`, `employer size class`, `legal form of organization`).

## Key fields
| Field | Description |
|---|---|
| `fipstate` / `fipscty` | State and county FIPS codes (geography key) |
| `naics2017` | NAICS industry code (2–6 digit) |
| `naics2017_label` | Industry description |
| `empszes` | Employer size class bucket (e.g., 1-4, 5-9, 10-19, 20-49, 50-99, 100-249, 250-499, 500+) |
| `estab` | Establishment count |
| `emp` | Paid employment (pay period incl. March 12) |
| `qp1` | First-quarter payroll ($1,000s) |
| `ap` | Annual payroll ($1,000s) |
| `lfo` | Legal form of organization |

## Null policy
Census **suppresses small cell counts** for disclosure avoidance — a suppressed cell is blank/flagged, not zero. The reconciliation platform's merchant-segmentation weighting must exclude suppressed cells from denominator calculations rather than treating them as true zeros (would bias the distribution toward large-cell industries/geographies).

## Cadence
Annual. Low urgency — use the last available vintage until the Census Bureau publishes a new one (~mid-year release for the prior year).

## Lineage metadata
`vintage_year`, `source_file` (e.g., `cbp23co.zip`), `download_date`, `ingestion_timestamp`.

## Late data handling
No SLA — annual refresh is a scheduled manual/semi-automated task, not a daily pipeline dependency. If the current vintage is more than 18 months stale relative to today, flag a freshness warning (segmentation weights go stale slowly; this doesn't block reconciliation).
