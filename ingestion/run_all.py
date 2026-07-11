"""Run all three macro-source ingestions in sequence.

Usage:
    python run_all.py
"""
from __future__ import annotations

import cbp_ingest
import cpi_ingest
import frps_ingest


def main() -> None:
    print("=== FRPS ===")
    frps_ingest.main()
    print("\n=== CBP ===")
    cbp_ingest.main()
    print("\n=== CPI ===")
    cpi_ingest.main(cpi_ingest.datetime.now().year - 5, cpi_ingest.datetime.now().year)


if __name__ == "__main__":
    main()
