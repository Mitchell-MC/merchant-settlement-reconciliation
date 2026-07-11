-- Silver conformed grain: one row per bank posting. This is the "actual
-- cash" side of the reconciliation contract (see docs/kpi_contract.md #2).
-- Deliberately NOT pre-joined to settlement_batches here -- that join is the
-- reconciliation engine's job (int_reconciliation_matches), not a given.
{{ config(materialized='table') }}

select
    posting_id,
    merchant_id,
    cast(posting_date as date) as posting_date,
    cast(amount as decimal(18,2)) as amount,
    bank_reference,
    _source_system,
    _ingestion_timestamp,
    _batch_id
from {{ source('bronze', 'bank_movements') }}
