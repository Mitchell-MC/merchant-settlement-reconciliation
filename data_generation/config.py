"""Generation parameters for the synthetic merchant operations dataset.

Everything that controls output shape/volume lives here so a run is fully
reproducible from (seed, date range, merchant count) alone.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date


@dataclass(frozen=True)
class SegmentWeights:
    """Merchant segmentation distribution. Defaults are a reasonable placeholder
    mix; swap in CBP-derived weights (see docs/source_contracts/cbp.md) once
    the reference download is wired up in Phase 2 ingestion.
    """

    industries: dict = field(default_factory=lambda: {
        "retail": 0.22,
        "restaurant_food_service": 0.18,
        "professional_services": 0.15,
        "ecommerce_online_retail": 0.15,
        "health_wellness": 0.10,
        "home_trade_services": 0.10,
        "auto_services": 0.06,
        "other": 0.04,
    })

    regions: dict = field(default_factory=lambda: {
        "Northeast": 0.18,
        "Midwest": 0.21,
        "South": 0.38,
        "West": 0.23,
    })

    employer_size_classes: dict = field(default_factory=lambda: {
        "1-4": 0.45,
        "5-9": 0.22,
        "10-19": 0.14,
        "20-49": 0.10,
        "50-99": 0.05,
        "100-249": 0.03,
        "250-499": 0.008,
        "500+": 0.002,
    })

    risk_tiers: dict = field(default_factory=lambda: {
        "standard": 0.80,
        "elevated": 0.15,
        "high": 0.05,
    })


@dataclass(frozen=True)
class BreakInjectionRates:
    """Probability that a given settlement batch's bank posting exhibits each
    break pattern. Must sum to <= 1.0 (remainder is a clean, on-time match).
    """

    bank_posting_delay: float = 0.05   # posted 1-3 extra business days late, same amount
    reserve_timing_error: float = 0.03  # amount off by a reserve release miscalculation
    missing_posting: float = 0.015      # no posting at all within the reconciliation window
    split_posting: float = 0.01         # two postings summing to the expected amount
    duplicate_posting: float = 0.005    # posting amount double-counted (bank-side error)


@dataclass(frozen=True)
class GenerationConfig:
    seed: int = 42
    start_date: date = date(2026, 1, 1)
    end_date: date = date(2026, 6, 30)
    merchant_count: int = 300

    avg_daily_transactions_per_merchant: float = 18.0
    refund_rate: float = 0.02

    interchange_fee_bps: int = 175       # 1.75% blended interchange, typical card-present/e-comm mix
    network_fee_bps: int = 10            # 0.10% network assessment
    base_processing_fee_bps: int = 40    # Meridian's markup, tiered by risk tier in settlement.py

    reserve_hold_window_days: int = 90   # rolling reserve released ~90 days after hold
    return_lag_days_min: int = 1
    return_lag_days_max: int = 21

    segments: SegmentWeights = field(default_factory=SegmentWeights)
    breaks: BreakInjectionRates = field(default_factory=BreakInjectionRates)

    output_dir: str = "data/bronze"
    ground_truth_dir: str = "data/generated"

    source_system: str = "synthetic_ops_generator"
