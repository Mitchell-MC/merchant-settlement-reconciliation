-- Gold: the triage-ready exception queue -- what an ops/finance analyst
-- would actually work off of, with a suggested owner and severity instead
-- of a raw break list.
--
-- Incremental merge, keyed on settlement_batch_id, with merge_update_columns
-- scoped to ONLY the recon-engine-owned columns (aging, amounts, severity,
-- suggested_owner_role, sla_due_date). triage_status/triage_notes/
-- triage_owner are intentionally excluded from merge_update_columns, so once
-- an analyst sets them via a downstream UPDATE they survive every future
-- run's merge instead of being clobbered back to 'new' -- this is the fix
-- for the persistence gap this model used to document as a known scoped-out
-- limitation (see git history). triage_status only gets a value on INSERT
-- (a genuinely new break), never on UPDATE.
--
-- fct_reconciliation_breaks (the source) only contains CURRENTLY OPEN
-- breaks -- a resolved break simply disappears from it, and a merge alone
-- never sees that absence, so a resolved break would sit in this queue
-- forever showing stale triage state. The post-hook below closes out any
-- row whose settlement_batch_id is no longer in the upstream open-break set
-- by setting triage_status = 'resolved' (not deleting it) -- preserves the
-- resolution itself as a queue entry rather than silently vanishing it.
{{
    config(
        materialized='incremental',
        unique_key='settlement_batch_id',
        incremental_strategy='merge',
        merge_update_columns=[
            'business_name', 'industry', 'region', 'risk_tier',
            'batch_date', 'break_first_identified_date', 'report_date',
            'expected_settlement_amount', 'actual_cash_received', 'break_amount',
            'age_business_days', 'aging_bucket', 'is_cash_at_risk',
            'funding_cost_estimate', 'root_cause_hint',
            'suggested_owner_role', 'severity', 'sla_due_date',
        ],
        post_hook="
            update {{ this }} q
            set triage_status = 'resolved'
            where q.triage_status not in ('resolved')
              and not exists (
                  select 1 from {{ ref('fct_reconciliation_breaks') }} br
                  where br.settlement_batch_id = q.settlement_batch_id
              )
        ",
    )
}}

select
    br.settlement_batch_id,
    br.merchant_id,
    mer.business_name,
    br.industry,
    br.region,
    br.risk_tier,
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
        when br.root_cause_hint = 'delayed' then 'Treasury Ops'
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
