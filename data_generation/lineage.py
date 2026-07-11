"""Bronze landing metadata -- applied uniformly to every generated table."""
from __future__ import annotations

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
