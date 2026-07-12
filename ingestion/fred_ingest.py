"""FRED (Federal Reserve Economic Data) rate series ingestion.

See docs/source_contracts/fred.md for the full contract. Pulls two monthly
rate series relevant to the funding-cost assumption in the Gold layer
(docs/kpi_contract.md, "Funding Cost Estimate": `assumed_cost_of_funds_rate`)
and lands a Bronze table at grain (series_id, observation_date).

Unlike the BLS API used for CPI, FRED requires an API key on every request --
there is no unauthenticated fallback. Register one (free, instant) at
https://fred.stlouisfed.org/docs/api/api_key.html and set FRED_API_KEY in
the environment before running this script.

Usage:
    python fred_ingest.py [--start-date 2021-01-01] [--end-date 2026-06-30]
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

API_URL = "https://api.stlouisfed.org/fred/series/observations"
SERIES_IDS = {
    "FEDFUNDS": "effective_federal_funds_rate",
    "MPRIME": "bank_prime_loan_rate",
}
SOURCE_SYSTEM = "fred_ingest"
OUTPUT_TABLE = "fred_rates"


def _fetch(series_id: str, start_date: str, end_date: str, api_key: str) -> list[dict]:
    params = {
        "series_id": series_id,
        "api_key": api_key,
        "file_type": "json",
        "observation_start": start_date,
        "observation_end": end_date,
    }
    resp = requests.get(API_URL, params=params, timeout=30)
    resp.raise_for_status()
    body = resp.json()
    return body["observations"]


def _parse_observations(series_id: str, series_type: str, observations: list[dict]) -> pd.DataFrame:
    rows = []
    for obs in observations:
        # FRED uses "." for a suppressed/not-yet-reported observation -- per
        # the null policy in docs/source_contracts/fred.md, that's a missing
        # row, not a zero, so skip it rather than coercing (same policy as
        # cpi_ingest.py's BLS "-" handling).
        if obs["value"] in (None, ".", ""):
            continue
        rows.append({
            "series_id": series_id,
            "series_type": series_type,
            "observation_date": obs["date"],
            "value": float(obs["value"]),
        })
    return pd.DataFrame(rows)


def main(start_date: str, end_date: str) -> None:
    api_key = os.environ.get("FRED_API_KEY")
    if not api_key:
        raise RuntimeError(
            "FRED_API_KEY is not set. Register a free key at "
            "https://fred.stlouisfed.org/docs/api/api_key.html and set it "
            "in the environment -- FRED requires a key on every request "
            "(no unauthenticated fallback, unlike the BLS CPI ingest)."
        )

    run_id = str(uuid.uuid4())
    print(f"Fetching FRED series {list(SERIES_IDS)} for {start_date}..{end_date}")

    frames = []
    for series_id, series_type in SERIES_IDS.items():
        observations = _fetch(series_id, start_date, end_date, api_key)
        frames.append(_parse_observations(series_id, series_type, observations))
    df = pd.concat(frames, ignore_index=True)
    df["pulled_at"] = datetime.now(timezone.utc).isoformat()

    landed = add_lineage(df, SOURCE_SYSTEM, run_id)
    out_path = write_landed_parquet(landed, str(PROJECT_ROOT / "data" / "bronze"), OUTPUT_TABLE)

    print(f"Landed {len(landed)} rows -> {out_path}")
    latest = df.sort_values("observation_date").groupby("series_id").tail(1)
    print(latest[["series_id", "observation_date", "value"]].to_string(index=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ingest rate series from the FRED API.")
    parser.add_argument("--start-date", default="2021-01-01")
    parser.add_argument("--end-date", default=datetime.now().strftime("%Y-%m-%d"))
    args = parser.parse_args()
    main(args.start_date, args.end_date)
