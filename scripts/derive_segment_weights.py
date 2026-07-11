"""Recompute data_generation/config.py's SegmentWeights defaults from the
locally-ingested CBP Bronze table. Prints new dict literals to paste in --
does not write the file itself, since the mapping/assumption choices
(retail/ecommerce split, "other" cap) are judgment calls a human should
review, not silently overwrite.

Run ingestion/cbp_ingest.py first to (re)produce data/bronze/cbp_establishments/.

Usage:
    python scripts/derive_segment_weights.py
"""
from __future__ import annotations

from pathlib import Path

import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# CBP reports combined sectors (31-33 manufacturing, 44-45 retail incl.
# nonstore/e-commerce, 48-49 transportation) under a single leading 2-digit
# code -- 45/32/33/49 don't appear as their own rows in the county file.
NAICS_TO_INDUSTRY = {
    "72----": "restaurant_food_service",
    "54----": "professional_services",
    "62----": "health_wellness",
    "23----": "home_trade_services",
    "81----": "auto_services",
}
RETAIL_COMBINED = "44----"
RETAIL_SPLIT = {"retail": 0.80, "ecommerce_online_retail": 0.20}  # documented assumption
OTHER_SHARE = 0.05  # see SegmentWeights docstring for rationale

FIPS_TO_STATE = {
    "01": "AL", "02": "AK", "04": "AZ", "05": "AR", "06": "CA", "08": "CO", "09": "CT",
    "10": "DE", "11": "DC", "12": "FL", "13": "GA", "15": "HI", "16": "ID", "17": "IL",
    "18": "IN", "19": "IA", "20": "KS", "21": "KY", "22": "LA", "23": "ME", "24": "MD",
    "25": "MA", "26": "MI", "27": "MN", "28": "MS", "29": "MO", "30": "MT", "31": "NE",
    "32": "NV", "33": "NH", "34": "NJ", "35": "NM", "36": "NY", "37": "NC", "38": "ND",
    "39": "OH", "40": "OK", "41": "OR", "42": "PA", "44": "RI", "45": "SC", "46": "SD",
    "47": "TN", "48": "TX", "49": "UT", "50": "VT", "51": "VA", "53": "WA", "54": "WV",
    "55": "WI", "56": "WY",
}
REGION_STATES = {
    "Northeast": ["CT", "ME", "MA", "NH", "RI", "VT", "NJ", "NY", "PA"],
    "Midwest": ["IL", "IN", "MI", "OH", "WI", "IA", "KS", "MN", "MO", "NE", "ND", "SD"],
    "South": ["DE", "FL", "GA", "MD", "NC", "SC", "VA", "DC", "WV", "AL", "KY", "MS", "TN", "AR", "LA", "OK", "TX"],
    "West": ["AZ", "CO", "ID", "MT", "NV", "NM", "UT", "WY", "AK", "CA", "HI", "OR", "WA"],
}
STATE_TO_REGION = {s: r for r, states in REGION_STATES.items() for s in states}


def main() -> None:
    df = pd.read_parquet(PROJECT_ROOT / "data" / "bronze" / "cbp_establishments" / "cbp_establishments.parquet")

    df["industry"] = df["naics_code"].map(NAICS_TO_INDUSTRY)
    mapped = df.dropna(subset=["industry"]).groupby("industry")["establishment_count"].sum()

    retail_total = df.loc[df["naics_code"] == RETAIL_COMBINED, "establishment_count"].sum()
    all_industry_counts = dict(mapped)
    all_industry_counts.update({k: retail_total * v for k, v in RETAIL_SPLIT.items()})

    mapped_sum = sum(all_industry_counts.values())
    scale = (1 - OTHER_SHARE) / mapped_sum
    industry_weights = {k: round(v * scale, 4) for k, v in all_industry_counts.items()}
    industry_weights["other"] = round(1 - sum(industry_weights.values()), 4)

    print("industries: dict = field(default_factory=lambda: {")
    for k, v in sorted(industry_weights.items(), key=lambda x: -x[1]):
        print(f'    "{k}": {v},')
    print("})\n")

    df["state_abbr"] = df["state_fips"].map(FIPS_TO_STATE)
    df["region"] = df["state_abbr"].map(STATE_TO_REGION)
    region_counts = df.dropna(subset=["region"]).groupby("region")["establishment_count"].sum()
    region_weights = (region_counts / region_counts.sum()).round(4)

    print("regions: dict = field(default_factory=lambda: {")
    for k, v in region_weights.sort_values(ascending=False).items():
        print(f'    "{k}": {v},')
    print("})\n")

    size_cols_raw = ["1-4", "5-9", "10-19", "20-49", "50-99", "100-249", "250-499", "500-999", "1000+"]
    size_totals = df[size_cols_raw].sum()
    size_totals["500+"] = size_totals["500-999"] + size_totals["1000+"]
    size_totals = size_totals.drop(["500-999", "1000+"])
    size_weights = (size_totals / size_totals.sum()).round(4)

    print("employer_size_classes: dict = field(default_factory=lambda: {")
    for k, v in size_weights.items():
        print(f'    "{k}": {v},')
    print("})")


if __name__ == "__main__":
    main()
