-- Gold: internal payment mix vs. the Federal Reserve Payments Study
-- national benchmark. Answers "is our channel mix and average ticket
-- typical, or are we concentrated somewhere the industry isn't" -- the
-- benchmark/context BI page.
--
-- GRAIN CAVEAT (read before interpreting any variance column): this is a
-- deliberately coarse comparison, not a like-for-like one.
--   * Internal rows are OUR settled card sales, split by acceptance
--     channel (card_present / ecommerce) -- the only split the source
--     transactions carry.
--   * FRPS rows are NATIONAL totals split by card TYPE (debit / credit).
--   * The two splits are not the same dimension, so only the `Cards`
--     roll-up line is genuinely comparable. Per-channel rows carry the
--     national share for context but must NOT be read as "we are X% above
--     the debit benchmark" -- there is no channel-level FRPS equivalent.
-- avg_ticket_usd is the one field that compares cleanly at every level:
-- it is a per-transaction average on both sides.
--
-- FRPS is a triennial study (2015/2018/2021/2024), so the benchmark is
-- anchored to its most recent collection year rather than joined on date --
-- see the freshness: null exemption in _bronze__sources.yml.
{{ config(materialized='table') }}

with latest_collection_year as (
    select max(collection_year) as collection_year
    from {{ source('bronze', 'frps_payment_volumes') }}
),

-- hierarchy_level 3 under the Cards branch is the debit/credit split;
-- level 2 'Cards' is their parent total. category_path (not the repeated
-- payment_type_label) is the reliable selector -- see source description.
frps_cards as (
    select
        f.payment_type_label as benchmark_segment,
        f.count_billions,
        f.value_trillions_usd,
        f.avg_transaction_amount_usd as benchmark_avg_ticket_usd,
        f.collection_year
    from {{ source('bronze', 'frps_payment_volumes') }} f
    join latest_collection_year l on l.collection_year = f.collection_year
    where f.category_path in (
        'Total > Cards > Debit cards',
        'Total > Cards > Credit cards'
    )
),

frps_cards_total as (
    select
        f.count_billions,
        f.value_trillions_usd,
        f.avg_transaction_amount_usd as benchmark_avg_ticket_usd,
        f.collection_year
    from {{ source('bronze', 'frps_payment_volumes') }} f
    join latest_collection_year l on l.collection_year = f.collection_year
    where f.category_path = 'Total > Cards'
),

-- Sales only: refunds are a contra-flow and would understate both the
-- transaction count and the average ticket if netted in here. FRPS counts
-- gross payment activity the same way.
internal_by_channel as (
    select
        pc.payment_channel_group as internal_segment,
        count(*) as transaction_count,
        sum(t.amount) as gross_volume_usd,
        avg(t.amount) as internal_avg_ticket_usd
    from {{ source('bronze', 'transactions') }} t
    join {{ ref('dim_payment_channel') }} pc on pc.payment_channel = t.channel
    where t.transaction_type = 'sale'
    group by pc.payment_channel_group
),

internal_total as (
    select
        sum(transaction_count) as transaction_count,
        sum(gross_volume_usd) as gross_volume_usd
    from internal_by_channel
),

-- One 'Cards' roll-up row (the only strictly comparable line) plus one row
-- per internal acceptance channel for mix context.
combined as (
    select
        'Cards (all)' as segment,
        'roll_up' as segment_kind,
        i.transaction_count,
        cast(i.gross_volume_usd as decimal(18,2)) as gross_volume_usd,
        cast(1.0 as decimal(9,6)) as internal_share_of_volume,
        cast(i.gross_volume_usd / nullif(i.transaction_count, 0) as decimal(18,2)) as internal_avg_ticket_usd,
        cast(fc.benchmark_avg_ticket_usd as decimal(18,2)) as benchmark_avg_ticket_usd,
        cast(1.0 as decimal(9,6)) as benchmark_share_of_volume,
        fc.collection_year as benchmark_collection_year
    from internal_total i
    cross join frps_cards_total fc

    union all

    select
        c.internal_segment as segment,
        'acceptance_channel' as segment_kind,
        c.transaction_count,
        cast(c.gross_volume_usd as decimal(18,2)) as gross_volume_usd,
        cast(c.gross_volume_usd / nullif(t.gross_volume_usd, 0) as decimal(9,6)) as internal_share_of_volume,
        cast(c.internal_avg_ticket_usd as decimal(18,2)) as internal_avg_ticket_usd,
        cast(fc.benchmark_avg_ticket_usd as decimal(18,2)) as benchmark_avg_ticket_usd,
        -- Null on purpose: there is no acceptance-channel line in FRPS, so
        -- any per-channel "national share" would be fabricated. See the
        -- grain caveat in this model's header.
        cast(null as decimal(9,6)) as benchmark_share_of_volume,
        fc.collection_year as benchmark_collection_year
    from internal_by_channel c
    cross join internal_total t
    cross join frps_cards_total fc
)

select
    segment,
    segment_kind,
    transaction_count,
    gross_volume_usd,
    internal_share_of_volume,
    internal_avg_ticket_usd,
    benchmark_avg_ticket_usd,
    benchmark_share_of_volume,
    -- Positive => our average ticket runs richer than the national card
    -- average. This is the headline comparison; it is valid at every grain
    -- because both sides are per-transaction averages.
    cast(internal_avg_ticket_usd - benchmark_avg_ticket_usd as decimal(18,2)) as avg_ticket_variance_usd,
    benchmark_collection_year,
    '{{ invocation_id }}' as run_id,
    {{ dbt.current_timestamp() }} as as_of_date
from combined
order by segment_kind, gross_volume_usd desc
