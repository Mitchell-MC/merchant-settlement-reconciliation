"""Generation parameters for the synthetic merchant operations dataset.

Everything that controls output shape/volume lives here so a run is fully
reproducible from (seed, date range, merchant count) alone.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date


@dataclass(frozen=True)
class SegmentWeights:
    """Merchant segmentation distribution, derived from the 2023 CBP county
    file (see docs/source_contracts/cbp.md and ingestion/cbp_ingest.py).
    Regenerate via scripts/derive_segment_weights.py if a newer CBP vintage
    is ingested.

    Two documented judgment calls layered on the raw establishment counts:
    - CBP reports NAICS 44 (Retail Trade) and 45 (Nonstore Retailers, incl.
      e-commerce) as a single combined "44" sector at the 2-digit grain --
      there's no way to isolate online-only establishment counts from this
      file, so the combined total is split 80/20 retail/ecommerce as an
      assumption, not a measurement.
    - Raw establishment counts span the whole economy (manufacturing,
      wholesale, utilities...) which aren't realistic SMB card-processing
      customers for a payment facilitator. Using the raw ~35% "other" share
      would make an irrelevant residual the single largest merchant segment,
      so "other" is capped at a fixed 5% and the 7 named industries' *relative*
      proportions to each other (the real CBP signal) are rescaled to fill
      the remaining 95%.
    """

    industries: dict = field(default_factory=lambda: {
        "health_wellness": 0.1751,
        "professional_services": 0.1726,
        "retail": 0.1457,
        "home_trade_services": 0.1422,
        "auto_services": 0.1410,
        "restaurant_food_service": 0.1370,
        "other": 0.0500,
        "ecommerce_online_retail": 0.0364,
    })

    # Establishment counts by Census region, 2023 CBP county file, all mapped industries.
    regions: dict = field(default_factory=lambda: {
        "South": 0.3692,
        "West": 0.2509,
        "Midwest": 0.2011,
        "Northeast": 0.1787,
    })

    # Establishment counts by employer size class, 2023 CBP county file
    # (national, all sectors); CBP's "500-999" and "1000+" buckets are
    # merged into "500+" to match this project's coarser taxonomy.
    employer_size_classes: dict = field(default_factory=lambda: {
        "1-4": 0.5610,
        "5-9": 0.1755,
        "10-19": 0.1246,
        "20-49": 0.0897,
        "50-99": 0.0283,
        "100-249": 0.0153,
        "250-499": 0.0036,
        "500+": 0.0019,
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
