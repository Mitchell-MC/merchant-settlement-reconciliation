{{ config(materialized='table') }}

select distinct
    channel as payment_channel,
    case
        when channel = 'card_present' then 'In-Person'
        when channel = 'ecommerce' then 'Online'
        else 'Other'
    end as payment_channel_group
from {{ source('bronze', 'transactions') }}
