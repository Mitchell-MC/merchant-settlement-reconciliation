# RBAC Role Model and Access Matrix

This is implemented, not aspirational: 4 Unity Catalog account-level groups exist in the live workspace (`dbc-08add949-9c19.cloud.databricks.com`) with the grants below applied via `GRANT` statements, verified with `SHOW GRANTS`. Full enterprise IAM federation (SSO/SCIM provisioning real distinct humans into these groups) is out of scope per [charter/PROJECT_CHARTER.md](../charter/PROJECT_CHARTER.md) — the groups and grants exist and are correct; assigning real people to them is a deployment-time exercise, not a data-platform one.

## Role model

| Role (UC group) | Maps to (Phase 1 stakeholder) | What they need |
|---|---|---|
| `recon_engineering` | Data/Analytics Engineering | Full read/write across all schemas — builds and operates the pipeline |
| `recon_treasury_viewers` | CFO, VP Treasury | Aggregate cash position and funding cost numbers — no merchant-level detail |
| `recon_finance_analysts` | Controller/Accounting, Head of Merchant Operations | Full investigative detail (Silver + all of Gold, including merchant-identifiable breaks) — they triage individual breaks |
| `recon_bi_consumers` | Broader company/exec reporting audience | Trend and volume views only, merchant identity masked |

Risk & Compliance (Phase 1 stakeholder map) isn't a distinct group here — in this build they'd use `recon_finance_analysts` access; a real rollout might split out a dedicated compliance role with read access to `reserve_events`/`returns_adjustments` for chargeback pattern monitoring.

## Access matrix

| Object | Sensitivity | `recon_engineering` | `recon_finance_analysts` | `recon_treasury_viewers` | `recon_bi_consumers` |
|---|---|---|---|---|---|
| `bronze.*` (raw, granular) | High — raw transactions, bank references | ALL PRIVILEGES | none | none | none |
| `silver.*` (conformed) | Medium-high — still batch/posting-level detail | ALL PRIVILEGES | SELECT | none | none |
| `gold.fct_daily_cash_position` | Low — aggregated, no merchant identity | ALL PRIVILEGES | SELECT | SELECT | SELECT |
| `gold.fct_funding_cost_summary` | Low — aggregated by segment | ALL PRIVILEGES | SELECT | SELECT | SELECT |
| `gold.fct_reconciliation_breaks` / `fct_exception_queue` / `fct_merchant_exception_trends` | Medium — merchant name + break amount | ALL PRIVILEGES | SELECT | none | none |
| `gold.vw_exception_queue_masked` | Low — pseudonymized | ALL PRIVILEGES | SELECT (redundant with above) | none | SELECT |
| `ops.*` (telemetry) | Internal — operational metadata, not business data | ALL PRIVILEGES | none | none | none |

## Verified grants (live, as of this build)

```
GRANT USE CATALOG ON CATALOG merchant_recon_project TO `recon_engineering`;
GRANT ALL PRIVILEGES ON CATALOG merchant_recon_project TO `recon_engineering`;

GRANT USE CATALOG ON CATALOG merchant_recon_project TO `recon_finance_analysts`;
GRANT USE SCHEMA ON SCHEMA merchant_recon_project.silver TO `recon_finance_analysts`;
GRANT SELECT ON SCHEMA merchant_recon_project.silver TO `recon_finance_analysts`;
GRANT USE SCHEMA ON SCHEMA merchant_recon_project.gold TO `recon_finance_analysts`;
GRANT SELECT ON SCHEMA merchant_recon_project.gold TO `recon_finance_analysts`;

GRANT USE CATALOG ON CATALOG merchant_recon_project TO `recon_treasury_viewers`;
GRANT USE SCHEMA ON SCHEMA merchant_recon_project.gold TO `recon_treasury_viewers`;
GRANT SELECT ON TABLE merchant_recon_project.gold.fct_daily_cash_position TO `recon_treasury_viewers`;
GRANT SELECT ON TABLE merchant_recon_project.gold.fct_funding_cost_summary TO `recon_treasury_viewers`;

GRANT USE CATALOG ON CATALOG merchant_recon_project TO `recon_bi_consumers`;
GRANT USE SCHEMA ON SCHEMA merchant_recon_project.gold TO `recon_bi_consumers`;
GRANT SELECT ON TABLE merchant_recon_project.gold.fct_daily_cash_position TO `recon_bi_consumers`;
GRANT SELECT ON TABLE merchant_recon_project.gold.fct_funding_cost_summary TO `recon_bi_consumers`;
GRANT SELECT ON VIEW merchant_recon_project.gold.vw_exception_queue_masked TO `recon_bi_consumers`;
```

Schema-level `SELECT` grants (e.g. on `silver`) cascade to all current and future tables in that schema — a new Silver model doesn't need a manual grant added.

## Known governance gap (found during verification, not fixed)

`SHOW GRANTS ON CATALOG merchant_recon_project` also lists an auto-created group `_workspace_users_merchant_recon_project_<id>` with blanket `USE CATALOG`, generated automatically when the catalog was created via Express workspace setup. This grants every workspace user baseline catalog visibility, which bypasses the tiered model above at the `USE CATALOG` level (object-level grants below it still apply correctly). A production hardening pass would revoke this default and rely solely on the 4 named groups — left as-is here and documented rather than silently fixed, since it's a real, common "secure by default isn't actually secure" finding worth calling out, not something to quietly paper over.
