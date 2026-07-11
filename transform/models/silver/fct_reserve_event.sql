{{ config(materialized='table') }}

select
    merchant_id,
    event_type,
    cast(event_date as date) as event_date,
    cast(related_date as date) as related_date,
    cast(amount as decimal(18,2)) as amount,
    _source_system,
    _ingestion_timestamp,
    _batch_id
from {{ source('bronze', 'reserve_events') }}
