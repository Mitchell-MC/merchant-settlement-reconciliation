"""The video's homework: force the pipeline to fail (loudly) on bad data.

Exercises common.validation -- the boundary contract that turns a silently
type-drifted column into a CRITICAL alert (and, on demand, a hard failure)
instead of a green pipeline landing garbage.
"""
from __future__ import annotations

import logging

import pandas as pd
import pytest

from common.validation import (
    BRONZE_SCHEMAS,
    DataContractViolation,
    validate_bronze,
    validate_frame,
)

SCHEMA = {"value": "numeric", "series_id": "string", "year": "int"}


def _clean_frame() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "series_id": ["CUUR0000SA0", "CUUR0000SA0"],
            "year": [2025, 2026],
            "value": [317.6, 320.1],
        }
    )


def test_clean_frame_passes_silently(caplog):
    with caplog.at_level(logging.CRITICAL):
        violations = validate_frame(_clean_frame(), "cpi_monthly", SCHEMA)
    assert violations == []
    assert caplog.records == []


def test_string_in_numeric_column_alerts(caplog):
    """The revenue-is-a-string scenario: alert loudly, name the offender.

    The frame is built with the string already in the column so the dtype is
    object -- assigning a str into a float64 column raises in modern pandas,
    which is itself the fail-loud behavior this whole change is about.
    """
    df = pd.DataFrame(
        {
            "series_id": ["CUUR0000SA0", "CUUR0000SA0"],
            "year": [2025, 2026],
            "value": [317.6, "not_a_number"],
        }
    )

    with caplog.at_level(logging.CRITICAL):
        violations = validate_frame(df, "cpi_monthly", SCHEMA)

    assert len(violations) == 1
    v = violations[0]
    assert v.column == "value"
    assert v.problem == "wrong_type"
    assert "not_a_number" in v.sample  # the actual offending payload, for triage
    assert any("DATA CONTRACT VIOLATION" in r.message and r.levelno == logging.CRITICAL for r in caplog.records)


def test_bad_data_can_hard_fail_when_asked():
    """raise_on_violation=True is the gate the dbt tests / a strict caller use."""
    df = pd.DataFrame({"series_id": ["CUUR0000SA0"], "year": [2025], "value": ["oops"]})
    with pytest.raises(DataContractViolation, match="value"):
        validate_frame(df, "cpi_monthly", SCHEMA, raise_on_violation=True)


def test_missing_required_column_is_a_violation():
    df = _clean_frame().drop(columns=["value"])
    violations = validate_frame(df, "cpi_monthly", SCHEMA)
    assert [v.problem for v in violations] == ["missing_column"]


def test_validate_bronze_uses_registered_schema():
    # transactions.amount is registered as numeric -- a string amount must fail.
    bad = pd.DataFrame({"amount": [10.0, "free"]})
    with pytest.raises(DataContractViolation):
        validate_bronze(bad, "transactions", raise_on_violation=True)


def test_validate_bronze_noop_for_unregistered_table(caplog):
    with caplog.at_level(logging.CRITICAL):
        assert validate_bronze(pd.DataFrame({"x": ["a"]}), "not_a_bronze_table") == []
    assert caplog.records == []


def test_registry_covers_the_money_columns():
    # Guard against someone deleting a contract: the money/number tables stay covered.
    for table in ("transactions", "settlement_batches", "bank_movements", "cpi_monthly"):
        assert table in BRONZE_SCHEMAS
