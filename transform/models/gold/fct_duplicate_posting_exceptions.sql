-- Gold: triage-ready surface for fct_duplicate_postings (Silver). Kept as
-- its own mart rather than merged into fct_exception_queue -- a duplicate
-- posting has no settlement_batch_id of its own (it duplicates a posting
-- that was already claimed by a real batch), so it doesn't share that
-- queue's grain, and forcing it in would break the queue's
-- unique(settlement_batch_id) test.
{{ config(materialized='table') }}

select
    dp.unclaimed_posting_id,
    dp.merchant_id,
    mer.business_name,
    mer.industry,
    mer.region,
    dp.posting_date,
    dp.amount,
    dp.duplicated_posting_id,
    dp.duplicated_against_batch_id,
    -- Same severity floor as fct_exception_queue's critical threshold --
    -- a duplicate payout is real cash out the door twice, so it's held to
    -- the same dollar bar as a critical break, not a lesser one.
    case when dp.amount >= 5000 then 'critical' else 'high' end as severity,
    'Treasury Ops' as suggested_owner_role,
    'new' as triage_status
from {{ ref('fct_duplicate_postings') }} dp
join {{ ref('dim_merchant') }} mer on mer.merchant_id = dp.merchant_id
