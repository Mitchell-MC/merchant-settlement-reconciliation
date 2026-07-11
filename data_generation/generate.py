"""Orchestrator: generate the full synthetic operational dataset and land it
as Bronze parquet, with a companion (never-ingested) ground-truth file for
deterministic reconciliation testing.

Usage:
    python generate.py [--seed 42] [--merchants 300]
"""
from __future__ import annotations

import argparse
import os
import uuid
from datetime import datetime, timezone

import pandas as pd

from bank_postings import generate_bank_postings
from config import GenerationConfig
from lineage import add_lineage
from merchants import generate_merchants
from settlement import generate_settlement_batches
from transactions import generate_transactions


def _write_parquet(df: pd.DataFrame, output_dir: str, table_name: str) -> str:
    table_dir = os.path.join(output_dir, table_name)
    os.makedirs(table_dir, exist_ok=True)
    path = os.path.join(table_dir, f"{table_name}.parquet")
    df.to_parquet(path, index=False)
    return path


def main(config: GenerationConfig | None = None) -> None:
    config = config or GenerationConfig()
    run_id = str(uuid.uuid4())
    started = datetime.now(timezone.utc)

    print(
        f"Run {run_id} | seed={config.seed} | "
        f"{config.start_date} -> {config.end_date} | merchants={config.merchant_count}"
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
        landed = add_lineage(df, config.source_system, run_id)
        path = _write_parquet(landed, config.output_dir, name)
        summary.append((name, len(landed), path))

    gt_path = os.path.join(config.ground_truth_dir, "ground_truth_breaks.parquet")
    ground_truth.to_parquet(gt_path, index=False)

    manifest_path = os.path.join(config.ground_truth_dir, "run_manifest.csv")
    pd.DataFrame(summary, columns=["table", "row_count", "path"]).to_csv(manifest_path, index=False)

    finished = datetime.now(timezone.utc)
    print(f"Completed in {(finished - started).total_seconds():.1f}s\n")
    for name, count, path in summary:
        print(f"  {name:<24} {count:>10,} rows -> {path}")
    print(f"  {'ground_truth_breaks':<24} {len(ground_truth):>10,} rows -> {gt_path}")

    print("\nInjected break scenario distribution:")
    print(ground_truth["injected_scenario"].value_counts().to_string())


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
