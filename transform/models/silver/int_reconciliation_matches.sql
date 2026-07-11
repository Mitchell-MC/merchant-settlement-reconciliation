{{
    config(
        materialized='table'
    )
}}

-- The reconciliation engine. Matches each settlement batch's expected
-- payout to actual bank cash using the date-window + amount-tolerance
-- policy in docs/non_functional_targets.md, implemented as vars in
-- dbt_project.yml so Treasury can change the policy without a code review
-- of this SQL.
--
-- Matching is a two-pass GREEDY algorithm, not a full assignment-problem
-- solver -- a deliberate, documented scope tradeoff (see charter's 5-minute
-- interview narrative):
--   Pass 1: mutual-nearest-neighbor single-posting match (handles the
--           overwhelming majority of batches -- clean matches and delayed
--           postings with the same amount).
--   Pass 2: for batches still unmatched, sum ALL unclaimed candidate
--           postings in the window -- handles split postings.
-- Anything left over is a genuine break.

with tolerance as (
    select
        {{ var('reconciliation_amount_tolerance_floor_usd') }} as floor_usd,
        {{ var('reconciliation_amount_tolerance_pct') }} as pct,
        {{ var('reconciliation_date_window_business_days') }} as window_business_days
),

batches as (
    select * from {{ ref('fct_settlement_batch') }}
),

postings as (
    select * from {{ ref('fct_bank_movement') }}
),

date_seq as (
    select date_day, business_day_seq from {{ ref('dim_date') }}
),

batch_with_seq as (
    select
        b.*,
        d.business_day_seq as payout_business_day_seq,
        greatest(t.floor_usd, t.pct * abs(b.expected_settlement_amount)) as amount_tolerance
    from batches b
    join date_seq d on d.date_day = b.expected_payout_date
    cross join tolerance t
),

batch_with_window as (
    select
        b.*,
        (
            select max(w.date_day)
            from date_seq w
            where w.business_day_seq = b.payout_business_day_seq + (select window_business_days from tolerance)
        ) as window_end_date
    from batch_with_seq b
),

candidates as (
    select
        b.settlement_batch_id,
        b.merchant_id,
        b.expected_settlement_amount,
        b.expected_payout_date,
        b.window_end_date,
        b.amount_tolerance,
        p.posting_id,
        p.posting_date,
        p.amount as posting_amount,
        abs(p.amount - b.expected_settlement_amount) as amount_diff,
        abs(datediff(p.posting_date, b.expected_payout_date)) as date_diff
    from batch_with_window b
    join postings p
        on p.merchant_id = b.merchant_id
       and p.posting_date between b.expected_payout_date and b.window_end_date
),

single_candidates as (
    select *
    from candidates
    where amount_diff <= amount_tolerance
),

ranked as (
    select
        c.*,
        row_number() over (
            partition by c.settlement_batch_id order by c.amount_diff asc, c.date_diff asc, c.posting_id asc
        ) as batch_rank,
        row_number() over (
            partition by c.posting_id order by c.amount_diff asc, c.date_diff asc, c.settlement_batch_id asc
        ) as posting_rank
    from single_candidates c
),

single_matches as (
    select
        settlement_batch_id,
        merchant_id,
        expected_settlement_amount,
        posting_amount as matched_amount,
        array(posting_id) as matched_posting_ids,
        'single_match' as match_method
    from ranked
    where batch_rank = 1 and posting_rank = 1
),

claimed_postings as (
    select posting_id from single_matches lateral view explode(matched_posting_ids) t as posting_id
),

unmatched_batches as (
    select b.*
    from batch_with_window b
    left join single_matches m on m.settlement_batch_id = b.settlement_batch_id
    where m.settlement_batch_id is null
),

split_candidates as (
    select
        c.settlement_batch_id,
        c.merchant_id,
        max(c.expected_settlement_amount) as expected_settlement_amount,
        max(c.amount_tolerance) as amount_tolerance,
        sum(c.posting_amount) as summed_amount,
        collect_list(c.posting_id) as posting_ids,
        count(*) as posting_count
    from candidates c
    join unmatched_batches ub on ub.settlement_batch_id = c.settlement_batch_id
    where c.posting_id not in (select posting_id from claimed_postings)
    group by c.settlement_batch_id, c.merchant_id
),

split_matches_raw as (
    select
        settlement_batch_id,
        merchant_id,
        expected_settlement_amount,
        summed_amount as matched_amount,
        posting_ids as matched_posting_ids,
        'split_match' as match_method
    from split_candidates
    where posting_count > 1
      and abs(summed_amount - expected_settlement_amount) <= amount_tolerance
),

-- split_candidates are computed independently per batch, so two batches for
-- the same merchant with overlapping windows can both claim the SAME
-- leftover postings -- that's not a false break, it's real cash being
-- double-counted across two obligations. Resolve conflicts deterministically:
-- earliest batch_date wins each posting; a batch that loses any one of its
-- claimed postings is fully invalidated (falls through to breaks) rather
-- than partially matched.
split_matches_exploded as (
    select sm.settlement_batch_id, bw.batch_date, posting_id
    from split_matches_raw sm
    join batch_with_window bw on bw.settlement_batch_id = sm.settlement_batch_id
    lateral view explode(sm.matched_posting_ids) t as posting_id
),

posting_winner as (
    select
        settlement_batch_id,
        posting_id,
        row_number() over (partition by posting_id order by batch_date asc, settlement_batch_id asc) as win_rank
    from split_matches_exploded
),

split_matches as (
    select sm.*
    from split_matches_raw sm
    where not exists (
        select 1 from posting_winner pw
        where pw.settlement_batch_id = sm.settlement_batch_id and pw.win_rank > 1
    )
),

matched as (
    select * from single_matches
    union all
    select * from split_matches
),

best_effort_for_breaks as (
    -- For batches that never matched, surface the closest same-merchant
    -- posting in-window (even outside tolerance) as a diagnostic hint --
    -- e.g. a reserve_timing_error break still has an obvious "this one"
    -- candidate, useful for root-cause triage in the Gold layer.
    select
        c.settlement_batch_id,
        c.posting_id as closest_posting_id,
        c.posting_amount as closest_posting_amount,
        c.amount_diff as closest_amount_diff,
        row_number() over (partition by c.settlement_batch_id order by c.amount_diff asc) as rn
    from candidates c
    join unmatched_batches ub on ub.settlement_batch_id = c.settlement_batch_id
    where c.settlement_batch_id not in (select settlement_batch_id from split_matches)
),

breaks as (
    select
        ub.settlement_batch_id,
        ub.merchant_id,
        ub.expected_settlement_amount,
        be.closest_posting_amount as matched_amount,
        case when be.closest_posting_id is not null then array(be.closest_posting_id) else array() end as matched_posting_ids,
        case when be.closest_posting_id is not null then 'unmatched_closest_candidate' else 'missing_posting' end as match_method
    from unmatched_batches ub
    left join best_effort_for_breaks be on be.settlement_batch_id = ub.settlement_batch_id and be.rn = 1
    where ub.settlement_batch_id not in (select settlement_batch_id from split_matches)
)

select
    b.settlement_batch_id,
    b.merchant_id,
    b.batch_date,
    b.expected_payout_date,
    b.window_end_date,
    b.expected_settlement_amount,
    coalesce(m.matched_amount, br.matched_amount) as actual_cash_received,
    coalesce(m.matched_posting_ids, br.matched_posting_ids, array()) as matched_posting_ids,
    coalesce(m.match_method, br.match_method) as match_method,
    case when m.settlement_batch_id is not null then true else false end as is_matched
from batch_with_window b
left join matched m on m.settlement_batch_id = b.settlement_batch_id
left join breaks br on br.settlement_batch_id = b.settlement_batch_id
