"""Bank posting generator with deliberately injected break patterns.

Each settlement batch is assigned exactly one scenario (clean match or one of
the break patterns in BreakInjectionRates). The scenario label is written to
a *separate* ground-truth table -- never into the Bronze bank_movement table
itself -- so the reconciliation engine has to actually detect breaks rather
than read an answer key. Seeded, so a given (seed, date range, merchant
count) always reproduces the same ground truth, which is what makes the
Phase 4 deterministic reconciliation tests possible.
"""
from __future__ import annotations

from datetime import timedelta

import numpy as np
import pandas as pd

from calendar_utils import next_business_day
from config import GenerationConfig


def _bank_reference(rng: np.random.Generator) -> str:
    return "".join(rng.choice(list("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789"), size=12))


def generate_bank_postings(
    settlement_batches: pd.DataFrame, config: GenerationConfig
) -> tuple[pd.DataFrame, pd.DataFrame]:
    rng = np.random.default_rng(config.seed + 3)
    b = config.breaks
    scenario_names = [
        "bank_posting_delay", "reserve_timing_error", "missing_posting",
        "split_posting", "duplicate_posting", "clean_match",
    ]
    scenario_probs = [
        b.bank_posting_delay, b.reserve_timing_error, b.missing_posting,
        b.split_posting, b.duplicate_posting,
    ]
    scenario_probs.append(max(0.0, 1.0 - sum(scenario_probs)))
    scenarios = rng.choice(scenario_names, size=len(settlement_batches), p=scenario_probs)

    posting_rows, ground_truth_rows = [], []
    posting_seq = 1

    for (row, scenario) in zip(settlement_batches.itertuples(index=False), scenarios):
        expected_amount = float(row.expected_settlement_amount)
        payout_date = row.expected_payout_date

        ground_truth_rows.append({
            "settlement_batch_id": row.settlement_batch_id,
            "merchant_id": row.merchant_id,
            "injected_scenario": scenario,
            "expected_settlement_amount": expected_amount,
        })

        if scenario == "clean_match":
            posting_rows.append({
                "posting_id": f"POST-{posting_seq:09d}", "merchant_id": row.merchant_id,
                "posting_date": payout_date, "amount": expected_amount,
                "bank_reference": _bank_reference(rng),
            })
            posting_seq += 1

        elif scenario == "bank_posting_delay":
            extra_days = int(rng.integers(1, 4))
            posting_rows.append({
                "posting_id": f"POST-{posting_seq:09d}", "merchant_id": row.merchant_id,
                "posting_date": next_business_day(payout_date, extra_days), "amount": expected_amount,
                "bank_reference": _bank_reference(rng),
            })
            posting_seq += 1

        elif scenario == "reserve_timing_error":
            reserve_ref = max(float(row.reserve_held), abs(expected_amount) * 0.01, 5.0)
            error_amount = round(rng.uniform(0.3, 1.0) * reserve_ref, 2)
            posting_rows.append({
                "posting_id": f"POST-{posting_seq:09d}", "merchant_id": row.merchant_id,
                "posting_date": payout_date, "amount": round(expected_amount - error_amount, 2),
                "bank_reference": _bank_reference(rng),
            })
            posting_seq += 1

        elif scenario == "missing_posting":
            pass  # deliberately no posting -- a genuine unresolved break

        elif scenario == "split_posting":
            split_pct = rng.uniform(0.3, 0.7)
            first = round(expected_amount * split_pct, 2)
            second = round(expected_amount - first, 2)
            second_date = payout_date if rng.random() < 0.5 else next_business_day(payout_date, 1)
            posting_rows.append({
                "posting_id": f"POST-{posting_seq:09d}", "merchant_id": row.merchant_id,
                "posting_date": payout_date, "amount": first, "bank_reference": _bank_reference(rng),
            })
            posting_seq += 1
            posting_rows.append({
                "posting_id": f"POST-{posting_seq:09d}", "merchant_id": row.merchant_id,
                "posting_date": second_date, "amount": second, "bank_reference": _bank_reference(rng),
            })
            posting_seq += 1

        elif scenario == "duplicate_posting":
            for _ in range(2):
                posting_rows.append({
                    "posting_id": f"POST-{posting_seq:09d}", "merchant_id": row.merchant_id,
                    "posting_date": payout_date, "amount": expected_amount,
                    "bank_reference": _bank_reference(rng),
                })
                posting_seq += 1

    return pd.DataFrame(posting_rows), pd.DataFrame(ground_truth_rows)
