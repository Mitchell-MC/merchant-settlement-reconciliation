-- Silver: bank postings that were never claimed by the reconciliation
-- engine (not a true match, not even the best-effort diagnostic candidate
-- on an open break) but share merchant/date/amount with a posting that WAS
-- claimed. That's the signature the generator's duplicate_posting scenario
-- leaves behind (data_generation/bank_postings.py posts the expected
-- settlement amount twice, same day): the engine correctly matches one of
-- the two, and the second sits in Bronze/Silver unflagged -- real cash with
-- no batch-side break to surface it, invisible until now.
--
-- Kept as its own model rather than folded into int_reconciliation_matches:
-- that model's grain contract (dbt_utils.equal_rowcount vs.
-- fct_settlement_batch, in _silver__models.yml) is one row per real
-- settlement batch, and a duplicate posting isn't a batch at all.
{{ config(materialized='table') }}

with postings as (
    select * from {{ ref('fct_bank_movement') }}
),

matches as (
    select * from {{ ref('int_reconciliation_matches') }}
),

claimed_postings as (
    -- Both true matches and best-effort diagnostic candidates on open
    -- breaks count as "claimed" -- a duplicate is only interesting when
    -- it's sitting completely outside any reconciliation story.
    -- Grouped down to one row per posting_id: a diagnostic candidate can be
    -- listed against more than one open break's matched_posting_ids, and
    -- without this the final join below fans out -- one output row per
    -- settlement_batch_id the posting happens to be associated with,
    -- instead of one per unclaimed posting (breaks this model's
    -- unclaimed_posting_id uniqueness contract in _silver__models.yml).
    select f.value::string as posting_id, min(settlement_batch_id) as settlement_batch_id
    from matches, lateral flatten(input => matched_posting_ids) f
    group by f.value::string
),

unclaimed as (
    select p.*
    from postings p
    left join claimed_postings cp on cp.posting_id = p.posting_id
    where cp.posting_id is null
)

select
    u.posting_id as unclaimed_posting_id,
    u.merchant_id,
    u.posting_date,
    u.amount,
    claimed.posting_id as duplicated_posting_id,
    claimed.settlement_batch_id as duplicated_against_batch_id
from unclaimed u
join postings claimed_posting on claimed_posting.merchant_id = u.merchant_id
    and claimed_posting.posting_date = u.posting_date
    and claimed_posting.amount = u.amount
    and claimed_posting.posting_id != u.posting_id
join claimed_postings claimed on claimed.posting_id = claimed_posting.posting_id
