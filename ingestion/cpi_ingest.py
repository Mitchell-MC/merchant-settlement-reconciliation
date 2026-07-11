"""CPI (Consumer Price Index) ingestion via the BLS Public Data API v2.

See docs/source_contracts/cpi.md for the full contract. Pulls the two
CPI-U all-items series (not seasonally adjusted and seasonally adjusted)
for a rolling window of years and lands a Bronze table at grain
(series_id, year, period).

An API key is optional (raises the daily query/series/year limits -- see
the source contract) -- set BLS_API_KEY in the environment to use one; the
script runs fine without it for a single pull like this.

Usage:
    python cpi_ingest.py [--start-year 2021] [--end-year 2026]
"""
from __future__ import annotations

import argparse
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import requests

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))
from common.lineage import add_lineage, write_landed_parquet  # noqa: E402

API_URL = "https://api.bls.gov/publicAPI/v2/timeseries/data/"
SERIES_IDS = {
    "CUUR0000SA0": "not_seasonally_adjusted",
    "CUSR0000SA0": "seasonally_adjusted",
}
SOURCE_SYSTEM = "cpi_ingest"
OUTPUT_TABLE = "cpi_monthly"


def _fetch(start_year: int, end_year: int) -> dict:
    payload = {
        "seriesid": list(SERIES_IDS.keys()),
        "startyear": str(start_year),
        "endyear": str(end_year),
    }
    api_key = os.environ.get("BLS_API_KEY")
    if api_key:
        payload["registrationkey"] = api_key

    resp = requests.post(API_URL, json=payload, timeout=30)
    resp.raise_for_status()
    body = resp.json()
    if body.get("status") != "REQUEST_SUCCEEDED":
        raise RuntimeError(f"BLS API request failed: {body.get('message')}")
    return body


def _parse_response(body: dict) -> pd.DataFrame:
    rows = []
    for series in body["Results"]["series"]:
        series_id = series["seriesID"]
        for point in series["data"]:
            # BLS uses "-" for a period with no value yet (not released) --
            # per the null policy in docs/source_contracts/cpi.md, that's a
            # missing row, not a zero, so skip it rather than coercing.
            if point["value"] in (None, "-", ""):
                continue
            rows.append({
                "series_id": series_id,
                "series_type": SERIES_IDS.get(series_id, "unknown"),
                "year": int(point["year"]),
                "period": point["period"],
                "period_name": point["periodName"],
                "value": float(point["value"]),
                "footnote_codes": ",".join(fn["code"] for fn in point.get("footnotes", []) if fn.get("code")),
            })
    return pd.DataFrame(rows)


def main(start_year: int, end_year: int) -> None:
    run_id = str(uuid.uuid4())

    print(f"Fetching CPI series {list(SERIES_IDS)} for {start_year}-{end_year}")
    body = _fetch(start_year, end_year)
    df = _parse_response(body)
    df["pulled_at"] = datetime.now(timezone.utc).isoformat()

    landed = add_lineage(df, SOURCE_SYSTEM, run_id)
    out_path = write_landed_parquet(landed, str(PROJECT_ROOT / "data" / "bronze"), OUTPUT_TABLE)

    print(f"Landed {len(landed)} rows -> {out_path}")
    latest = df.sort_values(["year", "period"]).groupby("series_id").tail(1)
    print(latest[["series_id", "year", "period_name", "value"]].to_string(index=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ingest CPI monthly series from the BLS API.")
    parser.add_argument("--start-year", type=int, default=datetime.now().year - 5)
    parser.add_argument("--end-year", type=int, default=datetime.now().year)
    args = parser.parse_args()
    main(args.start_year, args.end_year)
