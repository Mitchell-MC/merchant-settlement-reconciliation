import pytest

from config import BreakInjectionRates, SegmentWeights

TOLERANCE = 1e-3


@pytest.mark.parametrize("field_name", ["industries", "regions", "employer_size_classes", "risk_tiers"])
def test_segment_weight_groups_sum_to_one(field_name):
    weights = getattr(SegmentWeights(), field_name)
    assert abs(sum(weights.values()) - 1.0) < TOLERANCE


def test_break_injection_rates_do_not_exceed_one():
    rates = BreakInjectionRates()
    total = (
        rates.bank_posting_delay
        + rates.reserve_timing_error
        + rates.missing_posting
        + rates.split_posting
        + rates.duplicate_posting
    )
    assert 0 <= total <= 1.0


def test_segment_weights_have_no_negative_values():
    weights = SegmentWeights()
    for field_name in ("industries", "regions", "employer_size_classes", "risk_tiers"):
        for value in getattr(weights, field_name).values():
            assert value >= 0
