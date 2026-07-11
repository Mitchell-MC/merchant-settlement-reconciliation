{{ config(materialized='table') }}

select
    transaction_id,
    merchant_id,
    cast(transaction_date as date) as transaction_date,
    transaction_timestamp,
    transaction_type,
    channel as payment_channel,
    cast(amount as decimal(18,2)) as amount,
    _source_system,
    _ingestion_timestamp,
    _batch_id
from {{ source('bronze', 'transactions') }}
