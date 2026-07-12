"""Run all four macro-source ingestions in sequence.

Usage:
    python run_all.py
"""
from __future__ import annotations

import cbp_ingest
import cpi_ingest
import fred_ingest
import frps_ingest


def main() -> None:
    print("=== FRPS ===")
    frps_ingest.main()
    print("\n=== CBP ===")
    cbp_ingest.main()
    print("\n=== CPI ===")
    cpi_ingest.main(cpi_ingest.datetime.now().year - 5, cpi_ingest.datetime.now().year)
    print("\n=== FRED ===")
    try:
        fred_ingest.main("2021-01-01", fred_ingest.datetime.now().strftime("%Y-%m-%d"))
    except RuntimeError as e:
        # Unlike the other three sources, FRED has no unauthenticated
        # fallback -- skip rather than fail the whole run if FRED_API_KEY
        # isn't set yet (see docs/source_contracts/fred.md).
        print(f"Skipped: {e}")


if __name__ == "__main__":
    main()
