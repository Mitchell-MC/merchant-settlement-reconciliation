-- fct_duplicate_postings must only ever surface postings the reconciliation
-- engine did NOT claim (neither a true match nor a best-effort diagnostic
-- candidate) -- if a "duplicate" is actually a claimed posting, the model's
-- own unclaimed-posting join logic has a defect, and this would silently
-- double-count real matched cash as duplicate cash.
with claimed_postings as (
    select f.value::string as posting_id
    from {{ ref('int_reconciliation_matches') }}, lateral flatten(input => matched_posting_ids) f
)
select dp.unclaimed_posting_id
from {{ ref('fct_duplicate_postings') }} dp
join claimed_postings cp on cp.posting_id = dp.unclaimed_posting_id
