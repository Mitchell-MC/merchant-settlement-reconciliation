"""Bronze landing metadata and parquet-write helper -- shared by the
synthetic operational data generator (data_generation/) and the public
macro-source ingestion scripts (ingestion/), so every Bronze table carries
the same lineage contract regardless of which side produced it.
"""
from __future__ import annotations

import os
from datetime import datetime, timezone

import pandas as pd


def _row_hash(df: pd.DataFrame) -> pd.Series:
    # Vectorized (pandas.util.hash_pandas_object hashes column-wise in C, not
    # row-by-row Python) -- a naive `.astype(str).agg("|".join, axis=1)` here
    # takes ~50s on a 1M-row table; this is ~1s. Not cryptographic, which is
    # fine: this is a content-change fingerprint for lineage/dedup, not a
    # security control.
    hashed = pd.util.hash_pandas_object(df, index=False)
    return hashed.apply(lambda v: format(v & 0xFFFFFFFFFFFFFFFF, "016x"))


def add_lineage(df: pd.DataFrame, source_system: str, run_id: str) -> pd.DataFrame:
    df = df.copy()
    df["_row_hash"] = _row_hash(df)
    df["_source_system"] = source_system
    df["_ingestion_timestamp"] = datetime.now(timezone.utc).isoformat()
    df["_batch_id"] = run_id
    return df


def write_landed_parquet(df: pd.DataFrame, output_dir: str, table_name: str) -> str:
    table_dir = os.path.join(output_dir, table_name)
    os.makedirs(table_dir, exist_ok=True)
    path = os.path.join(table_dir, f"{table_name}.parquet")
    df.to_parquet(path, index=False)
    return path
