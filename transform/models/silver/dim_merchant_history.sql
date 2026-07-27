-- Point-in-time merchant attributes, derived from dim_merchant_snapshot
-- (dbt SCD2). One row per (merchant_id, valid_from..valid_to) version, so a
-- consumer can join "what was this merchant's risk_tier/rate/speed as of
-- date X" instead of dim_merchant's current-state-only view. See
-- dim_merchant_snapshot.sql for why this exists.
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
    dbt_valid_from as valid_from,
    -- Open version (dbt_valid_to is null) reads as "still current" -- coalesce
    -- to a far-future date so a plain BETWEEN works for both open and closed
    -- versions without a separate is-current branch at every call site.
    coalesce(dbt_valid_to, cast('9999-12-31' as timestamp_tz)) as valid_to
from {{ ref('dim_merchant_snapshot') }}
