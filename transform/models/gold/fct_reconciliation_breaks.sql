-- Gold: break-level detail. Covers "unresolved breaks," "break aging," and
-- "root-cause summary" from the plan -- the latter two are cuts of this one
-- fact (group by aging_bucket, or by root_cause_hint) rather than separate
-- physical tables, which is a deliberate simplicity choice for this scope.
{{ config(materialized='table') }}

with assumptions as (
    select
        max(case when assumption_key = 'assumed_cost_of_funds_annual_rate' then assumption_value end) as cost_of_funds_rate,
        max(case when assumption_key = 'cash_at_risk_aging_threshold_business_days' then assumption_value end) as cash_at_risk_threshold_days
    from {{ ref('dim_finance_assumptions_seed') }}
),

matches as (
    select * from {{ ref('int_reconciliation_matches') }}
),

-- report_date = the latest date by which every batch's reconciliation
-- window has closed, i.e. the last day we have complete visibility. Using
-- anything later than this would misclassify still-pending batches (window
-- not yet closed) as breaks.
report_date_cte as (
    select max(window_end_date) as report_date from matches
),

date_seq as (
    select date_day, business_day_seq from {{ ref('dim_date') }}
),

report_seq as (
    select d.business_day_seq as report_business_day_seq, r.report_date
    from report_date_cte r
    join date_seq d on d.date_day = r.report_date
),

break_rows as (
    select
        m.settlement_batch_id,
        m.merchant_id,
        m.batch_date,
        m.expected_payout_date,
        m.window_end_date as break_first_identified_date,
        m.expected_settlement_amount,
        m.actual_cash_received,
        abs(m.expected_settlement_amount - coalesce(m.actual_cash_received, 0)) as break_amount,
        m.match_method as root_cause_hint,
        rs.report_date
    from matches m
    cross join report_seq rs
    where m.is_matched = false
),

aged as (
    select
        b.*,
        (rs.report_business_day_seq - d.business_day_seq) as age_business_days
    from break_rows b
    join report_seq rs on true
    join date_seq d on d.date_day = b.break_first_identified_date
)

select
    a.settlement_batch_id,
    a.merchant_id,
    mer.industry,
    mer.region,
    mer.risk_tier,
    a.batch_date,
    a.expected_payout_date,
    a.break_first_identified_date,
    a.report_date,
    a.expected_settlement_amount,
    a.actual_cash_received,
    a.break_amount,
    a.age_business_days,
    case
        when a.age_business_days <= 1 then '0-1'
        when a.age_business_days <= 3 then '2-3'
        when a.age_business_days <= 7 then '4-7'
        when a.age_business_days <= 14 then '8-14'
        else '15+'
    end as aging_bucket,
    (a.age_business_days > asum.cash_at_risk_threshold_days) as is_cash_at_risk,
    round(a.break_amount * a.age_business_days * asum.cost_of_funds_rate / 365, 2) as funding_cost_estimate,
    a.root_cause_hint
from aged a
join {{ ref('dim_merchant') }} mer on mer.merchant_id = a.merchant_id
cross join assumptions asum
