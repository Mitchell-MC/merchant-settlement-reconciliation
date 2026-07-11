"""CBP (County Business Patterns) ingestion.

See docs/source_contracts/cbp.md for the full contract. Downloads the
county-level flat file (a ZIP containing one CSV) and lands a Bronze table
filtered to top-level (2-digit) NAICS sector rows.

Note on scope: the full county file is ~1.1M rows (every county x every
NAICS aggregation level down to 6-digit). This project uses CBP as a
merchant-segmentation weighting signal (see data_generation/config.py's
SegmentWeights), not as a full replica of the source -- so this ingestion
keeps only the 2-digit sector grain (~50K rows: county x sector), which is
plenty of resolution for that purpose. Re-run with a lower --naics-digits
filter (or none) if a future use case needs finer industry detail.

Note on column names: the real cbp23co.txt column names (fipstate, fipscty,
naics, emp, qp1, ap, est, n<5...n1000_4) differ from the generic names in
docs/source_contracts/cbp.md (EMP, QP1, AP, ESTAB, EMPSZES) -- that doc
describes the *documented* CBP concepts; this script matches the *actual*
file header, which is the authoritative source for what's landed in Bronze.
There is no LFO (legal form of organization) column in the county file --
it's only in a separate CBP data product.

Usage:
    python cbp_ingest.py [--url <zip-url>] [--naics-digits 2]
"""
from __future__ import annotations

import argparse
import io
import sys
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import requests

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))
from common.lineage import add_lineage, write_landed_parquet  # noqa: E402

DEFAULT_URL = "https://www2.census.gov/programs-surveys/cbp/datasets/2023/cbp23co.zip"
VINTAGE_YEAR = 2023
SOURCE_SYSTEM = "cbp_ingest"
OUTPUT_TABLE = "cbp_establishments"

# Establishment-count-by-employer-size-class columns, per the CBP record layout.
SIZE_CLASS_COLUMNS = {
    "n<5": "1-4", "n5_9": "5-9", "n10_19": "10-19", "n20_49": "20-49",
    "n50_99": "50-99", "n100_249": "100-249", "n250_499": "250-499",
    "n500_999": "500-999", "n1000": "1000+",
}
NUMERIC_COLUMNS = ["emp", "qp1", "ap", "est"] + list(SIZE_CLASS_COLUMNS)


def _download(url: str, dest: Path) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    resp = requests.get(url, timeout=120)
    resp.raise_for_status()
    dest.write_bytes(resp.content)
    return dest


def _is_target_sector_row(naics: str, digits: int) -> bool:
    # CBP pads codes to 6 chars with dashes/slashes to denote aggregation
    # level, e.g. "11----" is the 2-digit sector total for NAICS 11.
    significant = naics.rstrip("-/")
    return len(significant) == digits and naics.endswith("-" * (6 - digits))


def _parse_csv(zip_path: Path, naics_digits: int) -> pd.DataFrame:
    with zipfile.ZipFile(zip_path) as zf:
        inner_name = [n for n in zf.namelist() if n.endswith(".txt")][0]
        with zf.open(inner_name) as f:
            df = pd.read_csv(io.TextIOWrapper(f, encoding="latin1"), dtype=str)

    df.columns = [c.strip().lower() for c in df.columns]
    df = df[df["naics"].apply(lambda x: _is_target_sector_row(x, naics_digits))].copy()

    # "N" = withheld/suppressed for disclosure avoidance -- a real null, not
    # a zero (see docs/source_contracts/cbp.md null policy). Everything else
    # in these columns is a plain integer count.
    for col in NUMERIC_COLUMNS:
        df[col] = df[col].replace("N", np.nan).astype(float)

    df = df.rename(columns={
        "fipstate": "state_fips", "fipscty": "county_fips", "naics": "naics_code",
        "emp": "employment", "qp1": "q1_payroll_usd_thousands", "ap": "annual_payroll_usd_thousands",
        "est": "establishment_count",
    })
    df = df.rename(columns=SIZE_CLASS_COLUMNS)
    return df.reset_index(drop=True)


def main(url: str = DEFAULT_URL, naics_digits: int = 2) -> None:
    run_id = str(uuid.uuid4())
    zip_path = Path(__file__).resolve().parent / "_downloads" / "cbp23co.zip"

    print(f"Downloading CBP county file from {url}")
    _download(url, zip_path)

    df = _parse_csv(zip_path, naics_digits)
    df["vintage_year"] = VINTAGE_YEAR
    df["source_file"] = Path(url).name
    df["pulled_at"] = datetime.now(timezone.utc).isoformat()

    landed = add_lineage(df, SOURCE_SYSTEM, run_id)
    out_path = write_landed_parquet(landed, str(PROJECT_ROOT / "data" / "bronze"), OUTPUT_TABLE)

    print(f"Landed {len(landed)} rows ({naics_digits}-digit NAICS sector grain) -> {out_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ingest the CBP county-level establishment file.")
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--naics-digits", type=int, default=2, help="NAICS aggregation level to keep (default: 2-digit sector)")
    args = parser.parse_args()
    main(args.url, args.naics_digits)
