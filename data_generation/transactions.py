"""Raw transaction generator (Bronze grain: one row per transaction).

Vectorized: computes a Poisson transaction count per (merchant, day) using
day-of-week and industry seasonality, then expands to individual rows in one
pass rather than looping per transaction.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from calendar_utils import date_range
from config import GenerationConfig

# Multiplier by weekday (Mon=0..Sun=6) per industry -- captures realistic
# seasonality (restaurants spike on weekends, B2B professional services drop off).
DOW_MULTIPLIERS = {
    "retail":                      [1.00, 0.95, 0.98, 1.02, 1.15, 1.35, 1.10],
    "restaurant_food_service":     [0.80, 0.80, 0.85, 0.95, 1.20, 1.55, 1.35],
    "professional_services":       [1.05, 1.08, 1.08, 1.05, 0.90, 0.20, 0.10],
    "ecommerce_online_retail":     [1.00, 1.02, 1.02, 1.03, 1.05, 0.95, 0.98],
    "health_wellness":             [1.02, 1.05, 1.05, 1.02, 0.95, 0.35, 0.15],
    "home_trade_services":         [1.05, 1.05, 1.05, 1.05, 1.00, 0.40, 0.15],
    "auto_services":               [1.00, 1.00, 1.00, 1.00, 1.05, 0.85, 0.30],
    "other":                       [1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00],
}

CARD_PRESENT_SHARE = {
    "retail": 0.85, "restaurant_food_service": 0.90, "professional_services": 0.40,
    "ecommerce_online_retail": 0.02, "health_wellness": 0.55, "home_trade_services": 0.35,
    "auto_services": 0.80, "other": 0.60,
}


def generate_transactions(merchants: pd.DataFrame, config: GenerationConfig) -> pd.DataFrame:
    rng = np.random.default_rng(config.seed + 1)
    dates = list(date_range(config.start_date, config.end_date))
    n_days = len(dates)
    n_merchants = len(merchants)

    weekdays = np.array([d.weekday() for d in dates])
    dow_mult_matrix = np.array([DOW_MULTIPLIERS[ind] for ind in merchants["industry"]])  # (n_merchants, 7)
    day_multipliers = dow_mult_matrix[:, weekdays]  # (n_merchants, n_days)

    lam = (
        config.avg_daily_transactions_per_merchant
        * merchants["daily_txn_volume_multiplier"].to_numpy()[:, None]
        * day_multipliers
    )
    counts = rng.poisson(lam)  # (n_merchants, n_days)

    merchant_idx_grid, day_idx_grid = np.meshgrid(np.arange(n_merchants), np.arange(n_days), indexing="ij")
    flat_counts = counts.ravel()
    merchant_idx_rep = np.repeat(merchant_idx_grid.ravel(), flat_counts)
    day_idx_rep = np.repeat(day_idx_grid.ravel(), flat_counts)
    total_txns = merchant_idx_rep.shape[0]

    merchant_ids = merchants["merchant_id"].to_numpy()[merchant_idx_rep]
    industries = merchants["industry"].to_numpy()[merchant_idx_rep]
    avg_tickets = merchants["avg_ticket_usd"].to_numpy()[merchant_idx_rep]
    txn_dates = np.array(dates, dtype=object)[day_idx_rep]

    is_refund = rng.random(total_txns) < config.refund_rate
    amounts = rng.lognormal(mean=np.log(np.maximum(avg_tickets, 1.0)), sigma=0.45, size=total_txns).round(2)
    amounts = np.where(is_refund, -amounts, amounts)

    card_present_p = np.array([CARD_PRESENT_SHARE[ind] for ind in industries])
    is_card_present = rng.random(total_txns) < card_present_p
    channel = np.where(is_card_present, "card_present", "ecommerce")

    seconds_offset = rng.integers(7 * 3600, 22 * 3600, size=total_txns)
    # Microsecond precision: Databricks' Parquet reader rejects INT64
    # TIMESTAMP(NANOS) (pandas' native datetime64[ns] default) with
    # PARQUET_TYPE_ILLEGAL -- Spark timestamps are microsecond-precision.
    timestamps = (pd.to_datetime(txn_dates) + pd.to_timedelta(seconds_offset, unit="s")).astype("datetime64[us]")

    df = pd.DataFrame({
        "transaction_id": [f"TXN-{i:09d}" for i in range(1, total_txns + 1)],
        "merchant_id": merchant_ids,
        "transaction_date": pd.to_datetime(txn_dates).date,
        "transaction_timestamp": timestamps,
        "transaction_type": np.where(is_refund, "refund", "sale"),
        "channel": channel,
        "amount": amounts,
    })
    return df.sort_values(["transaction_date", "merchant_id"]).reset_index(drop=True)
