"""Loads local Bronze parquet files into Snowflake via the internal
BRONZE_LANDING stage + COPY INTO (see infra_snowflake/stage.tf, and
infra_snowflake/README.md for why an internal stage was chosen over an
S3 + storage-integration design).

This step has no Databricks equivalent in this repo -- Bronze table
creation/loading there has always been a manual, out-of-repo process
(see docs/architecture.md's Snowflake retarget notes). Run after
data_generation/generate.py and/or ingestion/*.py, before
`dbt build --target snowflake`.

Each table is fully truncated and reloaded per run, matching the local
parquet files themselves (one file per table per run, full overwrite --
see data_generation/generate.py) rather than an incremental append.

Usage:
    python scripts/load_bronze_to_snowflake.py
    python scripts/load_bronze_to_snowflake.py --tables merchants,transactions
"""
from __future__ import annotations

import argparse
from pathlib import Path

import snowflake.connector
import yaml
from cryptography.hazmat.primitives import serialization

PROJECT_ROOT = Path(__file__).resolve().parent.parent
BRONZE_DIR = PROJECT_ROOT / "data" / "bronze"
PROFILES_PATH = PROJECT_ROOT / "transform" / "profiles.yml"

# Matches transform/models/bronze/_bronze__sources.yml -- fred_rates is
# deliberately excluded there too (no FRED_API_KEY in this environment).
BRONZE_TABLES = [
    "merchants",
    "transactions",
    "settlement_batches",
    "reserve_events",
    "returns_adjustments",
    "bank_movements",
    "frps_payment_volumes",
    "cbp_establishments",
    "cpi_monthly",
]


def _load_snowflake_target(profiles_path: Path, target_name: str) -> dict:
    with open(profiles_path, "r", encoding="utf-8") as f:
        profiles = yaml.safe_load(f)
    return profiles["merchant_reconciliation"]["outputs"][target_name]


def _connect(target: dict) -> snowflake.connector.SnowflakeConnection:
    key_path = Path(target["private_key_path"]).expanduser()
    with open(key_path, "rb") as f:
        private_key = serialization.load_pem_private_key(f.read(), password=None)
    private_key_bytes = private_key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    # QUOTED_IDENTIFIERS_IGNORE_CASE is set account-wide by
    # infra_snowflake/account_parameters.tf -- INFER_SCHEMA-driven CREATE
    # TABLE below preserves the Parquet files' exact (lowercase) column
    # case as a quoted identifier, and without that account setting every
    # dbt source query (which references columns unquoted) fails with
    # "invalid identifier". See that file for why it has to be account-
    # level rather than set here per-session.
    return snowflake.connector.connect(
        account=target["account"],
        user=target["user"],
        role=target.get("role"),
        warehouse=target["warehouse"],
        database=target["database"],
        schema="BRONZE",
        private_key=private_key_bytes,
    )


def load_table(cur, table: str) -> int:
    local_path = BRONZE_DIR / table / f"{table}.parquet"
    if not local_path.exists():
        print(f"  skip {table}: no local file at {local_path}")
        return 0

    stage_path = f"@BRONZE.BRONZE_LANDING/{table}"
    table_ref = f"BRONZE.{table.upper()}"
    put_uri = local_path.resolve().as_posix()

    cur.execute(f"PUT 'file://{put_uri}' {stage_path} AUTO_COMPRESS=FALSE OVERWRITE=TRUE")

    # CREATE OR REPLACE (not IF NOT EXISTS): Bronze here is a full
    # per-run overwrite, same as the local parquet file itself, so
    # recreating the table structure each run is consistent, not
    # incidental -- and it's what re-applies QUOTED_IDENTIFIERS_IGNORE_CASE
    # if a table was created before that session setting was added.
    cur.execute(f"""
        CREATE OR REPLACE TABLE {table_ref}
        USING TEMPLATE (
            SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*))
            FROM TABLE(
                INFER_SCHEMA(
                    LOCATION => '{stage_path}',
                    FILE_FORMAT => 'BRONZE.PARQUET_FORMAT'
                )
            )
        )
    """)

    cur.execute(f"""
        COPY INTO {table_ref}
        FROM {stage_path}
        FILE_FORMAT = (FORMAT_NAME = 'BRONZE.PARQUET_FORMAT')
        MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
        PURGE = TRUE
    """)

    cur.execute(f"SELECT COUNT(*) FROM {table_ref}")
    return cur.fetchone()[0]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tables", help="Comma-separated subset of tables to load (default: all)")
    parser.add_argument("--profiles-target", default="snowflake", help="Output name in transform/profiles.yml")
    args = parser.parse_args()

    tables = args.tables.split(",") if args.tables else BRONZE_TABLES
    target = _load_snowflake_target(PROFILES_PATH, args.profiles_target)

    conn = _connect(target)
    try:
        cur = conn.cursor()
        for table in tables:
            count = load_table(cur, table)
            print(f"  {table}: {count} rows loaded")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
