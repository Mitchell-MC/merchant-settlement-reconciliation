-- Gold: as-of-report_date summary of cash-at-risk and funding cost by
-- merchant segment (docs/kpi_contract.md #6, #7) -- the numbers Treasury
-- uses to size credit-line draws.
{#- see fct_daily_cash_position.sql for why copy_grants is needed here on Snowflake #}
{% if target.type == 'snowflake' %}
{{ config(materialized='table', copy_grants=true) }}
{% else %}
{{ config(materialized='table') }}
{% endif %}

select
    report_date,
    industry,
    region,
    risk_tier,
    count(*) as open_break_count,
    sum(break_amount) as total_break_amount,
    sum(case when is_cash_at_risk then break_amount else 0 end) as cash_at_risk_amount,
    sum(funding_cost_estimate) as total_funding_cost_estimate
from {{ ref('fct_reconciliation_breaks') }}
group by report_date, industry, region, risk_tier
