-- Report-safe view for the BI Consumers role (see docs/rbac_access_matrix.md).
-- Drops business_name and pseudonymizes merchant_id -- a wide BI audience
-- can see break volume/severity/aging trends by industry and region without
-- seeing which specific named merchant is having payment problems, which is
-- sensitive commercial information about that merchant's business health.
{{ config(materialized='view') }}

select
    sha2(merchant_id, 256) as merchant_token,
    industry,
    region,
    risk_tier,
    batch_date,
    aging_bucket,
    severity,
    is_cash_at_risk,
    suggested_owner_role,
    -- Amounts are rounded to the nearest $100 at this tier -- enough for
    -- trend/volume analysis, not enough to infer an exact merchant balance.
    round(break_amount, -2) as break_amount_rounded,
    round(funding_cost_estimate, 0) as funding_cost_estimate_rounded
from {{ ref('fct_exception_queue') }}
