"""Bronze landing metadata and parquet-write helper -- shared by the
synthetic operational data generator (data_generation/) and the public
macro-source ingestion scripts (ingestion/), so every Bronze table carries
the same lineage contract regardless of which side produced it.
"""
from __future__ import annotations

import os
from datetime import timezone

import pandas as pd


def _row_hash(df: pd.DataFrame) -> pd.Series:
    """Compute a per-row content fingerprint for lineage/dedup purposes.

    Args:
        df (pd.DataFrame): Frame to hash. Every row is hashed independently.

    Returns:
        pd.Series: Hex-encoded 64-bit hash per row, aligned to df's index.
    """
    # Vectorized (pandas.util.hash_pandas_object hashes column-wise in C, not
    # row-by-row Python) -- a naive `.astype(str).agg("|".join, axis=1)` here
    # takes ~50s on a 1M-row table; this is ~1s. Not cryptographic, which is
    # fine: this is a content-change fingerprint for lineage/dedup, not a
    # security control.
    hashed = pd.util.hash_pandas_object(df, index=False)
    return hashed.apply(lambda v: format(v & 0xFFFFFFFFFFFFFFFF, "016x"))


def add_lineage(df: pd.DataFrame, source_system: str, run_id: str) -> pd.DataFrame:
    """Stamp a frame with the shared Bronze lineage columns.

    Args:
        df (pd.DataFrame): Frame to stamp. Not mutated in place.
        source_system (str): Identifier for the producing system, e.g. "cbp".
        run_id (str): UUID of the generation/ingestion run that produced df.

    Returns:
        pd.DataFrame: Copy of df with _row_hash, _source_system,
            _ingestion_timestamp, and _batch_id columns added.
    """
    df = df.copy()
    df["_row_hash"] = _row_hash(df)
    df["_source_system"] = source_system
    # Must be a real timestamp, not .isoformat() text: Parquet carries the
    # dtype through INFER_SCHEMA into the Bronze table, and dbt's freshness
    # check (loaded_at_field: _ingestion_timestamp in
    # models/bronze/_bronze__sources.yml) errors with "Expected a timestamp
    # value ... but received value of type 'str'" if this lands as TEXT.
    df["_ingestion_timestamp"] = pd.Timestamp.now(tz=timezone.utc)
    df["_batch_id"] = run_id
    return df


def write_landed_parquet(df: pd.DataFrame, output_dir: str, table_name: str) -> str:
    """Write a frame to <output_dir>/<table_name>/<table_name>.parquet.

    Args:
        df (pd.DataFrame): Frame to write.
        output_dir (str): Base Bronze output directory.
        table_name (str): Table name; also used as the subdirectory and
            file stem.

    Returns:
        str: Path to the written parquet file.
    """
    table_dir = os.path.join(output_dir, table_name)
    os.makedirs(table_dir, exist_ok=True)
    path = os.path.join(table_dir, f"{table_name}.parquet")
    df.to_parquet(path, index=False)
    return path
