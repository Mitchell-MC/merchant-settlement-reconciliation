-- Gold: the triage-ready exception queue -- what an ops/finance analyst
-- would actually work off of, with a suggested owner and severity instead
-- of a raw break list.
--
-- Known limitation: this table is fully rebuilt every run (materialized as
-- `table`, not `incremental`), so a human-set triage_status/owner override
-- would NOT persist across runs in this build -- a real production version
-- would use an incremental merge keyed on settlement_batch_id, updating
-- only recon-engine-owned columns (aging, amount) and leaving human-owned
-- columns (triage_status, notes) untouched on existing rows. Scoped out
-- here to keep this a `table` model consistent with the rest of Gold;
-- flagged explicitly rather than silently pretending it's stateful.
{{ config(materialized='table') }}

select
    br.settlement_batch_id,
    br.merchant_id,
    mer.business_name,
    br.industry,
    br.batch_date,
    br.break_first_identified_date,
    br.report_date,
    br.expected_settlement_amount,
    br.actual_cash_received,
    br.break_amount,
    br.age_business_days,
    br.aging_bucket,
    br.is_cash_at_risk,
    br.funding_cost_estimate,
    br.root_cause_hint,
    case
        when br.root_cause_hint = 'missing_posting' then 'Treasury Ops'
        when br.root_cause_hint = 'unmatched_closest_candidate' then 'Controller / Accounting'
        else 'Data/Analytics Engineering'
    end as suggested_owner_role,
    case
        when br.is_cash_at_risk and br.break_amount >= 5000 then 'critical'
        when br.is_cash_at_risk then 'high'
        when br.aging_bucket in ('2-3', '4-7') then 'medium'
        else 'low'
    end as severity,
    dateadd(day, asum.cash_at_risk_threshold_days, br.break_first_identified_date) as sla_due_date,
    'new' as triage_status
from {{ ref('fct_reconciliation_breaks') }} br
join {{ ref('dim_merchant') }} mer on mer.merchant_id = br.merchant_id
cross join (
    select cast(max(case when assumption_key = 'cash_at_risk_aging_threshold_business_days' then assumption_value end) as int) as cash_at_risk_threshold_days
    from {{ ref('dim_finance_assumptions_seed') }}
) asum
