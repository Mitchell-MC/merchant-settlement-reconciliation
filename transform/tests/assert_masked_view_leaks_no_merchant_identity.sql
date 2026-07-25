-- Governance control, asserted rather than assumed: vw_exception_queue_masked
-- is the ONLY Gold object granted to RECON_BI_CONSUMERS (see
-- docs/rbac_access_matrix.md), and its whole purpose is that a wide BI
-- audience can see break trends without learning which named merchant is
-- having payment problems.
--
-- Two ways that guarantee silently breaks, neither of which any schema test
-- would catch:
--   1. the pseudonymization degrades to a passthrough (merchant_token starts
--      carrying the raw merchant_id), or
--   2. someone adds business_name back to the select list when extending the
--      view, reintroducing exactly the identifier the view exists to strip.
--
-- Both are checked here against the unmasked parent. A column-level `unique`
-- test on merchant_token cannot see either: a raw id is also unique, and a
-- leaked extra column is invisible to per-column tests.

with masked as (
    select * from {{ ref('vw_exception_queue_masked') }}
),

-- (1) The token must never equal any real merchant_id. sha2 output is hex,
-- so this can only match if the masking was removed or bypassed.
token_is_raw_id as (
    select
        m.merchant_token as offending_value,
        'merchant_token matches a raw merchant_id' as violation
    from masked m
    where m.merchant_token in (select merchant_id from {{ ref('dim_merchant') }})
),

-- (2) Column-presence check. Reads the warehouse catalog rather than the
-- relation itself: a banned column that is present but all-null is still a
-- leak waiting to be populated, and selecting it would fail to compile
-- rather than fail the test.
banned_columns as (
    select
        column_name as offending_value,
        'identifying column present in masked view' as violation
    from {{ target.database }}.information_schema.columns
    where table_schema = upper('{{ target.schema }}')
      and table_name = upper('vw_exception_queue_masked')
      and lower(column_name) in ('business_name', 'merchant_id')
)

select * from token_is_raw_id
union all
select * from banned_columns
