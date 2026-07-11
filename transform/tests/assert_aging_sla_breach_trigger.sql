-- Custom reconciliation assertion: aging SLA breach trigger. Any break that
-- has sat unresolved for 15+ business days should be loudly visible, not
-- quietly aggregated into a dashboard nobody's looking at. severity=warn
-- since old breaks can legitimately exist (e.g. a merchant offboarding
-- dispute) -- the point is visibility, not blocking the pipeline.
{{ config(severity='warn') }}

select *
from {{ ref('fct_reconciliation_breaks') }}
where aging_bucket = '15+'
