-- Silver conformed grain: one row per (merchant_id, batch_date). This is the
-- "expected settlement" side of the reconciliation contract (see
-- docs/kpi_contract.md #1).
{{ config(materialized='table') }}

select
    settlement_batch_id,
    merchant_id,
    cast(batch_date as date) as batch_date,
    cast(expected_payout_date as date) as expected_payout_date,
    transaction_count,
    cast(gross_sales_volume as decimal(18,2)) as gross_sales_volume,
    cast(same_day_refunds as decimal(18,2)) as same_day_refunds,
    cast(interchange_fees as decimal(18,2)) as interchange_fees,
    cast(network_fees as decimal(18,2)) as network_fees,
    cast(processing_fees as decimal(18,2)) as processing_fees,
    cast(reserve_held as decimal(18,2)) as reserve_held,
    cast(reserve_released as decimal(18,2)) as reserve_released,
    cast(returns_adjustments_amount as decimal(18,2)) as returns_adjustments_amount,
    cast(expected_settlement_amount as decimal(18,2)) as expected_settlement_amount,
    _source_system,
    _ingestion_timestamp,
    _batch_id
from {{ source('bronze', 'settlement_batches') }}
