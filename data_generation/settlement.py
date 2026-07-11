"""Settlement batch, reserve ledger, and returns/adjustments generation.

Aggregates the transaction-level table into daily per-merchant settlement
batches, then walks batches in chronological order per merchant to maintain
a reserve hold/release ledger (fixed 90-day window) and to inject lagged
return/chargeback adjustments -- the mechanisms that make expected
settlement diverge from a naive same-day sum, which is exactly what the
reconciliation engine has to untangle.
"""
from __future__ import annotations

from collections import defaultdict
from datetime import timedelta

import numpy as np
import pandas as pd

from calendar_utils import next_business_day
from config import GenerationConfig

RETURN_REASON_CODES = ["chargeback", "customer_return", "billing_dispute"]
DAILY_ADJUSTMENT_PROBABILITY = 0.03


def _aggregate_daily_volume(transactions: pd.DataFrame) -> pd.DataFrame:
    sales = transactions[transactions["transaction_type"] == "sale"]
    refunds = transactions[transactions["transaction_type"] == "refund"]

    gross = sales.groupby(["merchant_id", "transaction_date"])["amount"].sum().rename("gross_sales_volume")
    refund_sum = refunds.groupby(["merchant_id", "transaction_date"])["amount"].apply(lambda s: -s.sum()).rename("same_day_refunds")
    txn_count = transactions.groupby(["merchant_id", "transaction_date"]).size().rename("transaction_count")

    agg = pd.concat([gross, refund_sum, txn_count], axis=1).fillna(0.0).reset_index()
    agg["transaction_count"] = agg["transaction_count"].astype(int)
    # Keep any day with activity (sales and/or refunds) so refund totals never
    # get silently dropped -- a refund-only day still produces a (possibly
    # negative) settlement batch, which control-total tests can verify against.
    agg = agg[agg["transaction_count"] > 0].copy()
    agg = agg.sort_values(["transaction_date", "merchant_id"]).reset_index(drop=True)
    return agg


def generate_settlement_batches(
    transactions: pd.DataFrame, merchants: pd.DataFrame, config: GenerationConfig
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    rng = np.random.default_rng(config.seed + 2)
    agg = _aggregate_daily_volume(transactions)

    merchant_params = merchants.set_index("merchant_id")[
        ["reserve_rate_bps", "processing_fee_bps", "settlement_speed_business_days"]
    ].to_dict(orient="index")

    volume_lookup = {
        (row.merchant_id, row.transaction_date): row.gross_sales_volume for row in agg.itertuples(index=False)
    }

    reserve_release_queue: dict[str, dict] = defaultdict(dict)  # merchant_id -> {release_date: amount}

    batch_rows, reserve_event_rows, adjustment_rows = [], [], []
    batch_seq, adj_seq = 1, 1

    for row in agg.itertuples(index=False):
        merchant_id = row.merchant_id
        batch_date = row.transaction_date
        gross = round(float(row.gross_sales_volume), 2)
        refunds = round(float(row.same_day_refunds), 2)
        params = merchant_params[merchant_id]

        reserve_held = round(gross * params["reserve_rate_bps"] / 10000, 2)
        release_date = batch_date + timedelta(days=config.reserve_hold_window_days)
        reserve_released = round(reserve_release_queue[merchant_id].pop(batch_date, 0.0), 2)
        reserve_release_queue[merchant_id][release_date] = (
            reserve_release_queue[merchant_id].get(release_date, 0.0) + reserve_held
        )

        if reserve_held > 0:
            reserve_event_rows.append({
                "merchant_id": merchant_id, "event_type": "hold", "event_date": batch_date,
                "amount": reserve_held, "related_date": release_date,
            })
        if reserve_released > 0:
            reserve_event_rows.append({
                "merchant_id": merchant_id, "event_type": "release", "event_date": batch_date,
                "amount": reserve_released, "related_date": batch_date - timedelta(days=config.reserve_hold_window_days),
            })

        returns_amount = 0.0
        if rng.random() < DAILY_ADJUSTMENT_PROBABILITY:
            lag = int(rng.integers(config.return_lag_days_min, config.return_lag_days_max + 1))
            original_batch_date = batch_date - timedelta(days=lag)
            original_gross = volume_lookup.get((merchant_id, original_batch_date))
            if original_gross and original_gross > 0:
                pct = rng.uniform(0.02, 0.08)
                returns_amount = round(original_gross * pct, 2)
                adjustment_rows.append({
                    "adjustment_id": f"ADJ-{adj_seq:08d}", "merchant_id": merchant_id,
                    "adjustment_date": batch_date, "original_batch_date": original_batch_date,
                    "amount": returns_amount, "reason_code": rng.choice(RETURN_REASON_CODES),
                })
                adj_seq += 1

        interchange = round(gross * config.interchange_fee_bps / 10000, 2)
        network = round(gross * config.network_fee_bps / 10000, 2)
        processing = round(gross * params["processing_fee_bps"] / 10000, 2)

        expected_settlement = round(
            gross - refunds - interchange - network - processing - reserve_held + reserve_released - returns_amount,
            2,
        )
        payout_date = next_business_day(batch_date, int(params["settlement_speed_business_days"]))

        batch_rows.append({
            "settlement_batch_id": f"BATCH-{batch_seq:08d}",
            "merchant_id": merchant_id,
            "batch_date": batch_date,
            "transaction_count": int(row.transaction_count),
            "gross_sales_volume": gross,
            "same_day_refunds": refunds,
            "interchange_fees": interchange,
            "network_fees": network,
            "processing_fees": processing,
            "reserve_held": reserve_held,
            "reserve_released": reserve_released,
            "returns_adjustments_amount": returns_amount,
            "expected_settlement_amount": expected_settlement,
            "expected_payout_date": payout_date,
        })
        batch_seq += 1

    return (
        pd.DataFrame(batch_rows),
        pd.DataFrame(reserve_event_rows),
        pd.DataFrame(adjustment_rows),
    )
