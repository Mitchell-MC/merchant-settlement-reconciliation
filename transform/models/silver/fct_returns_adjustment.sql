{{ config(materialized='table') }}

select
    adjustment_id,
    merchant_id,
    cast(adjustment_date as date) as adjustment_date,
    cast(original_batch_date as date) as original_batch_date,
    cast(amount as decimal(18,2)) as amount,
    reason_code,
    _source_system,
    _ingestion_timestamp,
    _batch_id
from {{ source('bronze', 'returns_adjustments') }}
