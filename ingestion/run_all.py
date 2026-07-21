"""Run all four macro-source ingestions in sequence.

Usage:
    python run_all.py
"""
from __future__ import annotations

import sys
from pathlib import Path

import cbp_ingest
import cpi_ingest
import fred_ingest
import frps_ingest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from common.logging_setup import get_logger  # noqa: E402

logger = get_logger("ingestion.run_all")


def main() -> None:
    logger.info("=== FRPS ===")
    frps_ingest.main()
    logger.info("=== CBP ===")
    cbp_ingest.main()
    logger.info("=== CPI ===")
    cpi_ingest.main(cpi_ingest.datetime.now().year - 5, cpi_ingest.datetime.now().year)
    logger.info("=== FRED ===")
    try:
        fred_ingest.main("2021-01-01", fred_ingest.datetime.now().strftime("%Y-%m-%d"))
    except RuntimeError as e:
        # Unlike the other three sources, FRED has no unauthenticated
        # fallback -- skip rather than fail the whole run if FRED_API_KEY
        # isn't set yet (see docs/source_contracts/fred.md). Logged as a
        # WARNING so the skip is visible in the run output, never silent.
        logger.warning("FRED skipped: %s", e)


if __name__ == "__main__":
    main()
