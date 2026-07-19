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

## Snowflake retarget: same matrix, same verification discipline

This is also implemented and verified, not aspirational, against the live Snowflake account `DZVUEJF-DF04786`. Four account roles (`RECON_ENGINEERING`, `RECON_TREASURY_VIEWERS`, `RECON_FINANCE_ANALYSTS`, `RECON_BI_CONSUMERS`) reproduce the exact same matrix above via [infra_snowflake/grants.tf](../infra_snowflake/grants.tf) -- see [infra_snowflake/README.md](../infra_snowflake/README.md) for the mechanical differences (Snowflake needs an `ALL` + `FUTURE` grant pair where Databricks' schema-level `SELECT` cascades on its own; explicit warehouse `USAGE`; no `storage_root`-style drift gotcha).

Role name mapping (Databricks group -> Snowflake role):

| Databricks group | Snowflake role |
|---|---|
| `recon_engineering` | `RECON_ENGINEERING` |
| `recon_treasury_viewers` | `RECON_TREASURY_VIEWERS` |
| `recon_finance_analysts` | `RECON_FINANCE_ANALYSTS` |
| `recon_bi_consumers` | `RECON_BI_CONSUMERS` |

Verified via `SHOW GRANTS TO ROLE <x>` / `SHOW GRANTS ON <object>` against the live account:

```
-- RECON_TREASURY_VIEWERS
USAGE   DATABASE  MERCHANT_RECON_PROJECT_DEV
USAGE   SCHEMA    MERCHANT_RECON_PROJECT_DEV.GOLD
USAGE   WAREHOUSE BI_WH
SELECT  TABLE     MERCHANT_RECON_PROJECT_DEV.GOLD.FCT_DAILY_CASH_POSITION
SELECT  TABLE     MERCHANT_RECON_PROJECT_DEV.GOLD.FCT_FUNDING_COST_SUMMARY

-- RECON_BI_CONSUMERS
USAGE   DATABASE  MERCHANT_RECON_PROJECT_DEV
USAGE   SCHEMA    MERCHANT_RECON_PROJECT_DEV.GOLD
USAGE   WAREHOUSE BI_WH
SELECT  TABLE     MERCHANT_RECON_PROJECT_DEV.GOLD.FCT_DAILY_CASH_POSITION
SELECT  TABLE     MERCHANT_RECON_PROJECT_DEV.GOLD.FCT_FUNDING_COST_SUMMARY
SELECT  VIEW      MERCHANT_RECON_PROJECT_DEV.GOLD.VW_EXCEPTION_QUEUE_MASKED   -- and ONLY this role

-- RECON_FINANCE_ANALYSTS
USAGE   DATABASE  MERCHANT_RECON_PROJECT_DEV
USAGE   SCHEMA    MERCHANT_RECON_PROJECT_DEV.SILVER
USAGE   SCHEMA    MERCHANT_RECON_PROJECT_DEV.GOLD
SELECT  TABLE     (every table in SILVER and GOLD, via ALL + FUTURE schema grants)

-- RECON_ENGINEERING
ALL PRIVILEGES  DATABASE  MERCHANT_RECON_PROJECT_DEV
ALL PRIVILEGES  SCHEMA    BRONZE / SILVER / GOLD / OPS (each)
OWNERSHIP       every table/view it (via dbt) created
READ, WRITE     STAGE     BRONZE.BRONZE_LANDING
```

### A real gotcha this verification pass caught: grants silently wiped on rebuild

`SHOW GRANTS` first came back **missing** the treasury/bi_consumers SELECT grants and the masked-view grant entirely, despite Terraform reporting them applied successfully. Root cause: Snowflake's default `CREATE OR REPLACE TABLE`/`VIEW` (what dbt's table/view materializations compile to) **drops all existing grants on the object** when it's rebuilt -- unlike Unity Catalog, where a dbt-rebuilt table keeps its ACLs. A `dbt build` run *after* the Terraform grants were applied silently reset them back to just the owner's (`RECON_ENGINEERING`) privileges.

Fixed with `copy_grants=true` on the three affected models' `config()` (Snowflake-only, via a `{% if target.type == 'snowflake' %}` branch so Databricks is unaffected) -- see `transform/models/gold/fct_daily_cash_position.sql`, `fct_funding_cost_summary.sql`, `vw_exception_queue_masked.sql`. Verified the fix by rebuilding twice in a row and re-running `SHOW GRANTS` after each: the treasury/bi_consumers/masked-view grants now survive every rebuild. This is a real, non-obvious cross-platform behavioral difference worth knowing before trusting any Terraform-managed grant on a dbt-owned Snowflake object.

## Governance gap found during verification -- fixed by adopting Terraform

`SHOW GRANTS ON CATALOG merchant_recon_project` originally also listed an auto-created group `_workspace_users_merchant_recon_project_<id>` with blanket `USE CATALOG`, generated automatically when the catalog was created via Express workspace setup — every workspace user had baseline catalog visibility, bypassing the tiered model above at the `USE CATALOG` level.

This was fixed as a *side effect*, not a targeted patch: `databricks_grants` in Terraform (see [infra/grants.tf](../infra/grants.tf)) is authoritative per securable — it fully overwrites the grant list on `terraform apply` rather than adding to it. Declaring the catalog's grants as exactly the 4 RBAC groups and running `terraform apply` silently revoked the undeclared default grant along with it. Verified: `SHOW GRANTS ON CATALOG merchant_recon_project` now lists exactly the 4 groups above, nothing else. This is a real example of IaC adoption closing a drift-born security gap, not something staged for the write-up.
