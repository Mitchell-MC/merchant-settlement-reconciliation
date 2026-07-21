"""Boundary data-contract validation that ALERTS on bad data at ingest.

The failure mode this exists for: a schema drifts upstream -- a numeric column
starts arriving as strings, or a required column disappears -- and the pipeline
keeps running green while landing garbage, so the board reads wrong numbers for
weeks before anyone notices. That is the "ostrich" failure the platform's whole
fail-loud posture (source freshness gate, dead-man's-switch, structured logging)
is built to prevent, pulled all the way up to the row where the bad type first
appears.

Design choice (see the project decision log / commit): at the Bronze boundary
this ALERTS rather than hard-rejects. Bronze is append-only and raw by contract,
and the authoritative rejection gate is the dbt test suite downstream; landing
the row and screaming about it beats dropping it on the floor. So a violation
emits a CRITICAL, greppable, alert-channel-ready log line naming the exact
table/column/expected/actual/sample -- not a swallowed exception, and not a
silent pass. Callers that DO want a hard stop pass raise_on_violation=True (the
dbt tests and the #6 unit test use that path).

A CRITICAL log here is meant to route to the same alerting the pipeline jobs use
(the on_failure / ALERT_WEBHOOK_URL path in infra/jobs.tf and the Snowflake
workflows) once a log-forwarding sink is wired -- documented next step.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass

import pandas as pd

_DEFAULT_LOGGER = logging.getLogger("common.validation")


class DataContractViolation(Exception):
    """Raised (only when raise_on_violation=True) when a frame breaks its
    declared Bronze contract."""


@dataclass(frozen=True)
class Violation:
    table: str
    column: str
    problem: str  # "missing_column" | "wrong_type"
    expected: str
    actual: str | None = None
    sample: str | None = None

    def as_alert(self) -> str:
        return (
            f"DATA CONTRACT VIOLATION | table={self.table} | column={self.column} "
            f"| problem={self.problem} | expected={self.expected} "
            f"| actual={self.actual} | sample={self.sample}"
        )


def _first_nonconforming_numeric(series: pd.Series) -> str | None:
    """First value that can't be read as a number (the string in the revenue
    column), for the alert -- so 3am triage sees the actual offending payload,
    not just 'type mismatch'."""
    coerced = pd.to_numeric(series, errors="coerce")
    bad = series[coerced.isna() & series.notna()]
    return None if bad.empty else repr(bad.iloc[0])


def _check_column(df: pd.DataFrame, table: str, column: str, expected: str) -> Violation | None:
    if column not in df.columns:
        return Violation(table, column, "missing_column", expected, actual="<absent>")

    series = df[column]
    actual = str(series.dtype)

    if expected in ("numeric", "int", "float"):
        if not pd.api.types.is_numeric_dtype(series):
            return Violation(table, column, "wrong_type", expected, actual, _first_nonconforming_numeric(series))
        if expected == "int" and not pd.api.types.is_integer_dtype(series):
            return Violation(table, column, "wrong_type", expected, actual)
    elif expected == "datetime":
        if not pd.api.types.is_datetime64_any_dtype(series):
            return Violation(table, column, "wrong_type", expected, actual)
    elif expected == "string":
        if not (pd.api.types.is_object_dtype(series) or pd.api.types.is_string_dtype(series)):
            return Violation(table, column, "wrong_type", expected, actual)
    else:  # pragma: no cover - guards against a typo'd schema entry
        raise ValueError(f"Unknown expected kind {expected!r} for {table}.{column}")
    return None


def validate_frame(
    df: pd.DataFrame,
    table: str,
    schema: dict[str, str],
    *,
    raise_on_violation: bool = False,
    logger: logging.Logger | None = None,
) -> list[Violation]:
    """Validate df against {column: expected_kind}. Emit a CRITICAL alert per
    violation; return them. With raise_on_violation, raise DataContractViolation
    if any were found (after alerting)."""
    log = logger or _DEFAULT_LOGGER
    violations = [v for col, kind in schema.items() if (v := _check_column(df, table, col, kind))]

    for v in violations:
        log.critical(v.as_alert())

    if violations and raise_on_violation:
        raise DataContractViolation(
            f"{len(violations)} data-contract violation(s) on '{table}': "
            + "; ".join(f"{v.column}({v.problem})" for v in violations)
        )
    return violations


# Declared Bronze contracts. Keyed by the table name the generator/ingestion
# scripts write. Intentionally scoped to the money/number/id columns whose type
# drift would silently corrupt a KPI -- not an exhaustive column list (that is
# the dbt source tests' job). Extend as new typed columns matter.
BRONZE_SCHEMAS: dict[str, dict[str, str]] = {
    "transactions": {"amount": "numeric"},
    "settlement_batches": {
        "expected_settlement_amount": "numeric",
        "gross_sales_volume": "numeric",
    },
    "bank_movements": {"amount": "numeric"},
    "cpi_monthly": {"series_id": "string", "year": "int", "value": "numeric"},
}


def validate_bronze(
    df: pd.DataFrame,
    table: str,
    *,
    raise_on_violation: bool = False,
    logger: logging.Logger | None = None,
) -> list[Violation]:
    """Validate a landed Bronze frame against its registered contract. Tables
    with no registered schema are a no-op (nothing to assert yet)."""
    schema = BRONZE_SCHEMAS.get(table)
    if not schema:
        return []
    return validate_frame(df, table, schema, raise_on_violation=raise_on_violation, logger=logger)
