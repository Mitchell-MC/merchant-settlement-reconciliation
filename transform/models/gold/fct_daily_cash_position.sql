-- Gold: daily trend of expected vs. actual cash, and the KPI contract's
-- rate-based metrics (docs/kpi_contract.md #1, #2, #4, #8), grain = batch_date.
{{ config(materialized='table') }}

select
    batch_date,
    count(*) as settlement_batch_count,
    sum(case when is_matched then 1 else 0 end) as matched_batch_count,
    sum(case when not is_matched then 1 else 0 end) as break_count,
    sum(expected_settlement_amount) as total_expected_settlement_amount,
    sum(case when is_matched then actual_cash_received else 0 end) as total_actual_cash_received,
    sum(case when not is_matched then abs(expected_settlement_amount - coalesce(actual_cash_received, 0)) else 0 end) as unresolved_break_amount,
    round(sum(case when not is_matched then 1 else 0 end) / count(*), 4) as break_rate_count_basis,
    round(
        sum(case when not is_matched then abs(expected_settlement_amount - coalesce(actual_cash_received, 0)) else 0 end)
        / nullif(sum(expected_settlement_amount), 0),
        4
    ) as break_rate_dollar_basis,
    round(
        sum(case when is_matched then expected_settlement_amount else 0 end) / nullif(sum(expected_settlement_amount), 0),
        4
    ) as reconciliation_match_rate
from {{ ref('int_reconciliation_matches') }}
group by batch_date
order by batch_date
