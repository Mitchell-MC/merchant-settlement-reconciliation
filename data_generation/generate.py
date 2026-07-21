"""Orchestrator: generate the full synthetic operational dataset and land it
as Bronze parquet, with a companion (never-ingested) ground-truth file for
deterministic reconciliation testing.

Usage:
    python generate.py [--seed 42] [--merchants 300]
"""
from __future__ import annotations

import argparse
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from bank_postings import generate_bank_postings
from config import GenerationConfig
from merchants import generate_merchants
from settlement import generate_settlement_batches
from transactions import generate_transactions

from common.lineage import add_lineage, write_landed_parquet
from common.logging_setup import get_logger
from common.validation import validate_bronze

logger = get_logger("data_generation.generate")


def main(config: GenerationConfig | None = None) -> None:
    config = config or GenerationConfig()
    run_id = str(uuid.uuid4())
    started = datetime.now(timezone.utc)

    logger.info(
        "Run %s | seed=%s | %s -> %s | merchants=%s",
        run_id,
        config.seed,
        config.start_date,
        config.end_date,
        config.merchant_count,
    )

    merchants = generate_merchants(config)
    transactions = generate_transactions(merchants, config)
    settlement_batches, reserve_events, adjustments = generate_settlement_batches(
        transactions, merchants, config
    )
    bank_postings, ground_truth = generate_bank_postings(settlement_batches, config)

    tables = {
        "merchants": merchants,
        "transactions": transactions,
        "settlement_batches": settlement_batches,
        "reserve_events": reserve_events,
        "returns_adjustments": adjustments,
        "bank_movements": bank_postings,
    }

    os.makedirs(config.output_dir, exist_ok=True)
    os.makedirs(config.ground_truth_dir, exist_ok=True)

    summary = []
    for name, df in tables.items():
        # Alert on any type/shape drift in the money columns before landing.
        validate_bronze(df, name, logger=logger)
        landed = add_lineage(df, config.source_system, run_id)
        path = write_landed_parquet(landed, config.output_dir, name)
        summary.append((name, len(landed), path))

    gt_path = os.path.join(config.ground_truth_dir, "ground_truth_breaks.parquet")
    ground_truth.to_parquet(gt_path, index=False)

    manifest_path = os.path.join(config.ground_truth_dir, "run_manifest.csv")
    pd.DataFrame(summary, columns=["table", "row_count", "path"]).to_csv(manifest_path, index=False)

    finished = datetime.now(timezone.utc)
    logger.info("Completed in %.1fs", (finished - started).total_seconds())
    for name, count, path in summary:
        logger.info("  %-24s %10s rows -> %s", name, f"{count:,}", path)
    logger.info("  %-24s %10s rows -> %s", "ground_truth_breaks", f"{len(ground_truth):,}", gt_path)
    logger.info(
        "Injected break scenario distribution:\n%s",
        ground_truth["injected_scenario"].value_counts().to_string(),
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate synthetic merchant settlement operational data.")
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--merchants", type=int, default=None)
    args = parser.parse_args()

    cfg_kwargs = {}
    if args.seed is not None:
        cfg_kwargs["seed"] = args.seed
    if args.merchants is not None:
        cfg_kwargs["merchant_count"] = args.merchants

    main(GenerationConfig(**cfg_kwargs))
