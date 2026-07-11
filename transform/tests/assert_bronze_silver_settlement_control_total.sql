-- Finance-grade control total: Silver must be an exact passthrough of
-- Bronze for expected_settlement_amount -- if these ever diverge, a
-- transformation is silently dropping or double-counting money.
with totals as (
    select
        (select round(sum(expected_settlement_amount), 2) from {{ source('bronze', 'settlement_batches') }}) as bronze_total,
        (select round(sum(expected_settlement_amount), 2) from {{ ref('fct_settlement_batch') }}) as silver_total
)
select *
from totals
where abs(bronze_total - silver_total) > 0.01
