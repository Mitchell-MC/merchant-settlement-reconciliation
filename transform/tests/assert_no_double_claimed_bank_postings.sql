-- Integrity check on the reconciliation engine's exclusivity guarantee: a
-- bank posting must never be claimed by more than one TRUE match (is_matched
-- = true). Restricted to true matches deliberately -- unmatched breaks'
-- matched_posting_ids holds a "closest candidate" diagnostic hint (see
-- best_effort_for_breaks in int_reconciliation_matches.sql), which several
-- nearby unresolved breaks can legitimately all point to as their best
-- guess; that's not a claim, so it's expected and fine for those to overlap.
with exploded as (
    select settlement_batch_id, posting_id
    from {{ ref('int_reconciliation_matches') }}
    lateral view explode(matched_posting_ids) t as posting_id
    where is_matched = true
)
select posting_id, count(distinct settlement_batch_id) as claim_count
from exploded
group by posting_id
having count(distinct settlement_batch_id) > 1
