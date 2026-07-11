-- Custom reconciliation assertion: unmatched-rate ceiling. A single day's
-- dollar-basis break rate above 10% is a signal something upstream broke
-- (bad batch of source data, a calendar bug, a bank feed outage) -- not
-- routine noise. severity=warn: this should be loud, not block Gold
-- publication on its own (see docs/non_functional_targets.md).
{{ config(severity='warn') }}

select *
from {{ ref('fct_daily_cash_position') }}
where break_rate_dollar_basis > 0.10
