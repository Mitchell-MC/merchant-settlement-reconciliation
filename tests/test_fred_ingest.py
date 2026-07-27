import pytest

from fred_ingest import _parse_observations, main

SAMPLE_OBSERVATIONS = [
    {"realtime_start": "2026-01-01", "realtime_end": "2026-01-01", "date": "2026-01-01", "value": "5.33"},
    {
        # Suppressed/not-yet-reported observation: FRED uses "." as the placeholder.
        "realtime_start": "2026-02-01", "realtime_end": "2026-02-01", "date": "2026-02-01", "value": ".",
    },
    {"realtime_start": "2026-03-01", "realtime_end": "2026-03-01", "date": "2026-03-01", "value": "5.25"},
]


def test_parse_observations_skips_suppressed_placeholder_values():
    df = _parse_observations("FEDFUNDS", "effective_federal_funds_rate", SAMPLE_OBSERVATIONS)
    assert len(df) == 2
    assert "." not in df["value"].astype(str).tolist()


def test_parse_observations_parses_value_as_float():
    df = _parse_observations("FEDFUNDS", "effective_federal_funds_rate", SAMPLE_OBSERVATIONS)
    row = df[df["observation_date"] == "2026-01-01"].iloc[0]
    assert row["value"] == 5.33


def test_parse_observations_carries_series_metadata():
    df = _parse_observations("MPRIME", "bank_prime_loan_rate", SAMPLE_OBSERVATIONS)
    assert (df["series_id"] == "MPRIME").all()
    assert (df["series_type"] == "bank_prime_loan_rate").all()


def test_parse_observations_empty_list_returns_empty_frame():
    df = _parse_observations("FEDFUNDS", "effective_federal_funds_rate", [])
    assert len(df) == 0


def test_main_without_api_key_raises_runtime_error(monkeypatch):
    # Unlike cpi_ingest (BLS key is optional), FRED has no unauthenticated
    # fallback -- main() must fail loudly and *before* attempting any request
    # if FRED_API_KEY isn't set, not raise an opaque error from requests.
    monkeypatch.delenv("FRED_API_KEY", raising=False)
    with pytest.raises(RuntimeError, match="FRED_API_KEY"):
        main("2021-01-01", "2026-01-01")
