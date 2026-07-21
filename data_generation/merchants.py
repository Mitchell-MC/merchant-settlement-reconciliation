"""Merchant dimension generator.

Produces the static (as-of-generation-run) merchant reference table that all
daily operational entities key off of. Segmentation mix comes from
GenerationConfig.segments -- see docs/source_contracts/cbp.md for the real
CBP-derived weights this is designed to be swapped for.
"""
from __future__ import annotations

from datetime import timedelta

import numpy as np
import pandas as pd
from config import GenerationConfig

REGION_STATES = {
    "Northeast": ["CT", "ME", "MA", "NH", "RI", "VT", "NJ", "NY", "PA"],
    "Midwest": ["IL", "IN", "MI", "OH", "WI", "IA", "KS", "MN", "MO", "NE", "ND", "SD"],
    "South": ["DE", "FL", "GA", "MD", "NC", "SC", "VA", "DC", "WV", "AL", "KY", "MS", "TN", "AR", "LA", "OK", "TX"],
    "West": ["AZ", "CO", "ID", "MT", "NV", "NM", "UT", "WY", "AK", "CA", "HI", "OR", "WA"],
}

INDUSTRY_MCC = {
    "retail": "5311",
    "restaurant_food_service": "5812",
    "professional_services": "8742",
    "ecommerce_online_retail": "5964",
    "health_wellness": "8099",
    "home_trade_services": "1731",
    "auto_services": "7538",
    "other": "5999",
}

RISK_TIER_PARAMS = {
    # reserve_rate_bps of gross volume held; processing_fee_bps on top of config base;
    # settlement_speed_business_days = T+N payout timing
    "standard": {"reserve_rate_bps": 500, "processing_fee_bps_add": 0, "settlement_speed_business_days": 1},
    "elevated": {"reserve_rate_bps": 800, "processing_fee_bps_add": 15, "settlement_speed_business_days": 2},
    "high": {"reserve_rate_bps": 1200, "processing_fee_bps_add": 35, "settlement_speed_business_days": 2},
}

_NAME_PREFIXES = [
    "Northgate", "Blue Harbor", "Summit", "Cedar", "Lakeside", "Ironwood", "Golden State",
    "Riverstone", "Maple", "Union", "Pioneer", "Crescent", "Amber", "Bluebird", "Copper Creek",
    "Willow", "Granite", "Silver Line", "Harborview", "Cobalt", "Meadowbrook", "Redwood",
    "Anchor", "Vista", "Cascade", "Foxglove", "Emberly", "Stonegate", "Brightwater", "Timberline",
]
_NAME_SUFFIXES = {
    "retail": ["General Store", "Mercantile", "Outfitters", "Trading Co.", "Boutique"],
    "restaurant_food_service": ["Kitchen", "Grill", "Cafe", "Bistro", "Eatery"],
    "professional_services": ["Consulting Group", "Advisors", "Partners", "Associates"],
    "ecommerce_online_retail": ["Direct", "Online", "Marketplace", "Goods Co."],
    "health_wellness": ["Wellness Studio", "Clinic", "Health Collective", "Therapy Group"],
    "home_trade_services": ["Contracting", "Home Services", "Builders", "Trade Co."],
    "auto_services": ["Auto Care", "Motors", "Garage", "Auto Works"],
    "other": ["Enterprises", "Holdings", "Services", "Co."],
}


def _weighted_choice(rng: np.random.Generator, weights: dict, size: int) -> np.ndarray:
    keys = list(weights.keys())
    probs = np.array(list(weights.values()), dtype=float)
    probs = probs / probs.sum()
    return rng.choice(keys, size=size, p=probs)


def generate_merchants(config: GenerationConfig) -> pd.DataFrame:
    rng = np.random.default_rng(config.seed)
    n = config.merchant_count

    industries = _weighted_choice(rng, config.segments.industries, n)
    regions = _weighted_choice(rng, config.segments.regions, n)
    employer_sizes = _weighted_choice(rng, config.segments.employer_size_classes, n)
    risk_tiers = _weighted_choice(rng, config.segments.risk_tiers, n)

    states = np.array([rng.choice(REGION_STATES[r]) for r in regions])

    name_prefixes = rng.choice(_NAME_PREFIXES, size=n, replace=True)
    name_suffixes = [rng.choice(_NAME_SUFFIXES[ind]) for ind in industries]
    business_names = [f"{p} {s}" for p, s in zip(name_prefixes, name_suffixes)]

    onboarding_offsets = rng.integers(30, 365 * 3, size=n)
    onboarding_dates = [config.start_date - timedelta(days=int(o)) for o in onboarding_offsets]

    reserve_rate_bps = np.array([RISK_TIER_PARAMS[t]["reserve_rate_bps"] for t in risk_tiers])
    processing_fee_bps = np.array(
        [config.base_processing_fee_bps + RISK_TIER_PARAMS[t]["processing_fee_bps_add"] for t in risk_tiers]
    )
    settlement_speed = np.array(
        [RISK_TIER_PARAMS[t]["settlement_speed_business_days"] for t in risk_tiers]
    )

    avg_ticket = rng.lognormal(mean=3.2, sigma=0.6, size=n).round(2)  # ~$25 median ticket, long tail
    daily_txn_scale = rng.lognormal(mean=0.0, sigma=0.5, size=n)  # per-merchant volume multiplier

    df = pd.DataFrame({
        "merchant_id": [f"MER-{i:06d}" for i in range(1, n + 1)],
        "business_name": business_names,
        "industry": industries,
        "mcc": [INDUSTRY_MCC[ind] for ind in industries],
        "region": regions,
        "state": states,
        "employer_size_class": employer_sizes,
        "risk_tier": risk_tiers,
        "onboarding_date": onboarding_dates,
        "reserve_rate_bps": reserve_rate_bps,
        "processing_fee_bps": processing_fee_bps,
        "settlement_speed_business_days": settlement_speed,
        "avg_ticket_usd": avg_ticket,
        "daily_txn_volume_multiplier": daily_txn_scale.round(4),
    })
    return df
