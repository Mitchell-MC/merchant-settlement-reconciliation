-- Gold: per-merchant settlement SLA performance -- on-time rate, average
-- settlement delay, and exception counts by merchant segment and geography.
--
-- Distinct from fct_merchant_exception_trends, which summarises only the
-- OPEN break population (who owes us a fix right now). This model scores
-- EVERY settlement batch, matched or not, so a merchant that always settles
-- late-but-eventually-matched still shows a poor on-time rate here while
-- contributing nothing to the exception trends model.
--
-- Delay is measured in BUSINESS days via dim_date.business_day_seq, not
-- calendar days: a Friday batch posting Monday is on time under a T+1
-- contract, and datediff() would wrongly call it 3 days late. Same
-- business-day convention as docs/kpi_contract.md's cross-cutting rules.
{{ config(materialized='table') }}

with matches as (
    select * from {{ ref('int_reconciliation_matches') }}
),

date_seq as (
    select date_day, business_day_seq from {{ ref('dim_date') }}
),

-- Actual settlement date = the LAST posting that made the batch whole. For
-- a split match the batch is not settled until its final component lands,
-- so max() (not min()) is the correct cash-received date.
matched_posting_dates as (
{% if target.type == "snowflake" %}
    select
        m.settlement_batch_id,
        max(bm.posting_date) as actual_settlement_date
    from matches m,
        lateral flatten(input => m.matched_posting_ids) f
    join {{ ref('fct_bank_movement') }} bm on bm.posting_id = f.value::string
    where m.is_matched
    group by m.settlement_batch_id
{% else %}
    select
        m.settlement_batch_id,
        max(bm.posting_date) as actual_settlement_date
    from matches m
    lateral view explode(m.matched_posting_ids) t as posting_id
    join {{ ref('fct_bank_movement') }} bm on bm.posting_id = t.posting_id
    where m.is_matched
    group by m.settlement_batch_id
{% endif %}
),

batch_scored as (
    select
        m.settlement_batch_id,
        m.merchant_id,
        m.batch_date,
        m.expected_settlement_amount,
        m.is_matched,
        mpd.actual_settlement_date,
        -- Null for unmatched batches: cash never arrived, so a delay figure
        -- would be fiction. Those are counted as exceptions instead, and
        -- excluded from the average-delay denominator below.
        case
            when m.is_matched
            then ds_actual.business_day_seq - ds_expected.business_day_seq
        end as settlement_delay_business_days
    from matches m
    left join matched_posting_dates mpd on mpd.settlement_batch_id = m.settlement_batch_id
    left join date_seq ds_expected on ds_expected.date_day = m.expected_payout_date
    left join date_seq ds_actual on ds_actual.date_day = mpd.actual_settlement_date
),

-- On time = matched AND landed on or before the expected payout date
-- (delay <= 0). A negative delay (early posting) is still on time.
batch_flagged as (
    select
        b.*,
        case
            when b.is_matched and coalesce(b.settlement_delay_business_days, 0) <= 0
            then 1 else 0
        end as is_on_time,
        case when not b.is_matched then 1 else 0 end as is_exception
    from batch_scored b
)

select
    mer.merchant_id,
    mer.business_name,
    mer.industry,
    mer.region,
    mer.state,
    mer.risk_tier,
    mer.settlement_speed_business_days as contracted_settlement_speed_days,

    count(*) as settlement_batch_count,
    sum(b.is_on_time) as on_time_batch_count,
    sum(b.is_exception) as exception_batch_count,

    -- KPI: on-time settlement rate, the headline SLA-attainment number.
    cast(sum(b.is_on_time) / nullif(count(*), 0) as decimal(9,6)) as on_time_settlement_rate,

    -- Averaged over MATCHED batches only (unmatched have no delay value);
    -- exception_batch_count carries the rest of the story.
    cast(avg(b.settlement_delay_business_days) as decimal(9,2)) as avg_settlement_delay_business_days,
    max(b.settlement_delay_business_days) as max_settlement_delay_business_days,

    cast(sum(case when b.is_exception = 1 then b.expected_settlement_amount else 0 end) as decimal(18,2)) as exception_amount_usd,
    cast(sum(b.expected_settlement_amount) as decimal(18,2)) as total_expected_settlement_amount,

    '{{ invocation_id }}' as run_id,
    {{ dbt.current_timestamp() }} as as_of_date
from batch_flagged b
join {{ ref('dim_merchant') }} mer on mer.merchant_id = b.merchant_id
group by
    mer.merchant_id, mer.business_name, mer.industry, mer.region,
    mer.state, mer.risk_tier, mer.settlement_speed_business_days
order by on_time_settlement_rate asc
