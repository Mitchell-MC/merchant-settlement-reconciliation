{{ config(materialized='table') }}

select
    merchant_id,
    business_name,
    industry,
    mcc,
    region,
    state,
    employer_size_class,
    risk_tier,
    onboarding_date,
    reserve_rate_bps,
    processing_fee_bps,
    settlement_speed_business_days,
    avg_ticket_usd,
    _source_system,
    _ingestion_timestamp,
    _batch_id
from {{ source('bronze', 'merchants') }}
