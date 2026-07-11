-- Gold: merchant-level exception rollup -- who's driving break volume, and
-- how severe/aged is it. Feeds the ops drill-down BI page (Phase 9).
{{ config(materialized='table') }}

select
    mer.merchant_id,
    mer.business_name,
    mer.industry,
    mer.region,
    mer.risk_tier,
    count(*) as open_break_count,
    sum(br.break_amount) as total_break_amount,
    round(avg(br.age_business_days), 1) as avg_age_business_days,
    sum(case when br.is_cash_at_risk then 1 else 0 end) as cash_at_risk_break_count,
    sum(case when br.is_cash_at_risk then br.break_amount else 0 end) as cash_at_risk_amount,
    sum(br.funding_cost_estimate) as total_funding_cost_estimate,
    mode(br.root_cause_hint) as most_common_root_cause
from {{ ref('fct_reconciliation_breaks') }} br
join {{ ref('dim_merchant') }} mer on mer.merchant_id = br.merchant_id
group by mer.merchant_id, mer.business_name, mer.industry, mer.region, mer.risk_tier
order by total_break_amount desc
