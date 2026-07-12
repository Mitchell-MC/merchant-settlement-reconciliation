import dataclasses

from config import GenerationConfig
from merchants import INDUSTRY_MCC, generate_merchants

EXPECTED_COLUMNS = {
    "merchant_id", "business_name", "industry", "mcc", "region", "state",
    "employer_size_class", "risk_tier", "onboarding_date", "reserve_rate_bps",
    "processing_fee_bps", "settlement_speed_business_days", "avg_ticket_usd",
    "daily_txn_volume_multiplier",
}


def _small_config(seed: int = 42, merchant_count: int = 50) -> GenerationConfig:
    return dataclasses.replace(GenerationConfig(), seed=seed, merchant_count=merchant_count)


def test_generate_merchants_row_count_and_columns():
    df = generate_merchants(_small_config())
    assert len(df) == 50
    assert EXPECTED_COLUMNS.issubset(set(df.columns))


def test_generate_merchants_is_deterministic_for_same_seed():
    df1 = generate_merchants(_small_config(seed=7))
    df2 = generate_merchants(_small_config(seed=7))
    assert df1.equals(df2)


def test_generate_merchants_differs_for_different_seed():
    df1 = generate_merchants(_small_config(seed=1))
    df2 = generate_merchants(_small_config(seed=2))
    assert not df1["business_name"].equals(df2["business_name"])


def test_merchant_ids_are_unique():
    df = generate_merchants(_small_config(merchant_count=300))
    assert df["merchant_id"].is_unique
    assert len(df) == 300


def test_mcc_matches_industry_mapping():
    df = generate_merchants(_small_config())
    for industry, mcc in zip(df["industry"], df["mcc"]):
        assert mcc == INDUSTRY_MCC[industry]


def test_industry_values_are_known_segments():
    df = generate_merchants(_small_config(merchant_count=300))
    assert set(df["industry"].unique()).issubset(set(INDUSTRY_MCC.keys()))
