-- Custom reconciliation assertion: every batch the engine marked as
-- matched must actually satisfy the documented amount-tolerance policy
-- (docs/non_functional_targets.md). Guards against a future regression in
-- int_reconciliation_matches silently loosening the match criteria.
with tolerance as (
    select
        {{ var('reconciliation_amount_tolerance_floor_usd') }} as floor_usd,
        {{ var('reconciliation_amount_tolerance_pct') }} as pct
)
select m.*
from {{ ref('int_reconciliation_matches') }} m
cross join tolerance t
where m.is_matched = true
  and abs(m.expected_settlement_amount - m.actual_cash_received) > greatest(t.floor_usd, t.pct * abs(m.expected_settlement_amount)) + 0.01
