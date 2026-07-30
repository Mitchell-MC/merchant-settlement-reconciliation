# CLAUDE.md

Guidance for Claude Code when working in this repository (Merchant Settlement
Reconciliation & Cash Visibility — see [README.md](README.md) and
[charter/PROJECT_CHARTER.md](charter/PROJECT_CHARTER.md) for the business framing).

This file previously mirrored an unrelated project (a Canadian real-estate
market-data pipeline on pydantic/mypy/uv/TimescaleDB) that does not exist
here. This version reflects what this repo actually does and how it's
actually built, verified against the code, `pyproject.toml`,
`.github/workflows/ci.yml`, and git history.

## What this repo is

A batch reconciliation platform for a fictional payment facilitator
("Meridian Pay"): synthetic operational data + public macro reference data
(FRPS/CBP/CPI/FRED) land in Snowflake as Bronze, get conformed in
Silver, matched by a dbt reconciliation engine, and rolled up into a Gold
star schema for an executive dashboard. See
[docs/architecture.md](docs/architecture.md) for the full data flow.

## Repo layout

| Path | Contents |
|---|---|
| `data_generation/` | Deterministic synthetic operational data generator (merchants, transactions, settlement batches, bank postings) |
| `ingestion/` | FRPS / CBP / CPI / FRED macro reference data ingestion scripts |
| `common/` | Shared Bronze lineage/landing helpers (`lineage.py`), structured logging (`logging_setup.py`), boundary data-contract validation (`validation.py`) |
| `scripts/` | Operational scripts: segment-weight derivation, Snowflake Bronze load |
| `transform/` | dbt project — Bronze/Silver/Gold models, reconciliation logic, tests, snapshots, `ops` observability models |
| `infra_snowflake/` | Terraform for Snowflake (database, warehouses, roles/grants, service user, stage) |
| `tests/` | One top-level pytest suite covering `data_generation/`, `ingestion/`, and `common/` — **not** a per-module `tests/` layout |
| `docs/`, `charter/`, `bi/` | Source contracts, KPI/governance docs, runbooks; executive dashboard + Power BI project |

Python packages here are flat modules under each top-level directory (no
`src/` layout, no package `__init__.py` re-exports beyond `common/`) — new
Python code should follow that same flat, directory-per-concern shape
rather than introducing a `src/` tree or nested module packages.

## Environment & dev commands

This project uses **pip + per-slice `requirements*.txt` files**, not uv or a
single `[project.dependencies]` block — `pyproject.toml` only holds tool
config (ruff, pytest, coverage).

```bash
pip install -r requirements-dev.txt
pip install -r data_generation/requirements.txt -r ingestion/requirements.txt

# Lint (CI gate — undefined names, unused imports, import order; see
# pyproject.toml's [tool.ruff.lint] comment for why the rule set is
# explicit rather than ruff's shifting defaults)
ruff check .

# Tests (coverage is a ratchet: --cov-fail-under in pyproject.toml blocks
# merge if coverage drops; raise the floor as it grows, never lower it)
pytest tests/ -v --cov --cov-report=term-missing

# dbt (from transform/)
cd transform && dbt build --target snowflake
```

There is no mypy config or job in this repo — don't assume type-checking is
enforced in CI beyond what `ruff` catches.

## Style & conventions

- Python 3.12, `from __future__ import annotations`, PEP 604 unions
  (`str | None`) — not `Optional[...]`.
- Config/data shapes use **`@dataclass`**, not pydantic — pydantic isn't a
  dependency anywhere in this repo. Follow `data_generation/config.py`'s
  pattern (nested frozen dataclasses with `field(default_factory=...)` for
  dict/list defaults) for new config.
- **Every function gets a Google-style docstring** (Args/Returns/Raises as
  applicable) — including private (`_prefixed`) helpers. Test helper
  functions get one too; individual `test_*` functions don't need one when
  the test name is self-explanatory.
- Comments explain **why**, not what — see `common/lineage.py` and
  `common/validation.py` for the house style (a comment justifying a
  non-obvious choice, not restating the line below it).
- Structured logging (`common/logging_setup.py`'s `get_logger`) — never
  `print()` for anything except one-off code-generation output like
  `scripts/derive_segment_weights.py`.
- ruff config (`pyproject.toml`) intentionally selects only `F`, `E`, `I` —
  don't add `ANN`/`D`/`UP`/`RUF` etc. without discussing it, since a wider
  rule set is a merge gate that can turn red on an unrelated ruff upgrade.

## Testing

- New logic in `data_generation/`, `ingestion/`, or `common/` gets pytest
  tests in the top-level `tests/` directory (not a co-located `tests/`
  next to the module).
- Favor small, deterministic unit tests: seed-based determinism checks
  (`generate_merchants` with the same seed producing identical output) and
  parsing/validation tests with fixed input fixtures are the dominant
  pattern here — see `tests/test_merchants.py` and `tests/test_validation.py`.
- After changing generation/ingestion/validation logic, check whether the
  existing tests in the corresponding `tests/test_*.py` still hold.

## Branching & commits

There is no `develop` branch in this repo — git history shows work committed
directly to `master` with short, present-tense, descriptive messages (e.g.
"Add duplicate-posting detection...", "Fix Snowflake pipeline failures...").
Don't assume a `feature/`/`fix/` branch-naming convention is in force unless
the user asks for one explicitly for a given change.

## Security-sensitive patterns to preserve

- Snowflake auth is key-pair only (`scripts/load_bronze_to_snowflake.py`),
  reading the private key from `SNOWFLAKE_CI_PRIVATE_KEY` (CI) or a local
  path in `transform/profiles.yml` (dev) — never hardcode credentials.
- SQL identifiers built from table names must be validated against a known
  allowlist (`BRONZE_TABLES` in `load_bronze_to_snowflake.py`) before being
  interpolated into a query string.
- `common/validation.py`'s boundary contract check runs before data lands in
  Bronze — new ingestion/generation tables that carry money or key
  identifier columns should register a schema in `BRONZE_SCHEMAS` rather
  than skip validation.
