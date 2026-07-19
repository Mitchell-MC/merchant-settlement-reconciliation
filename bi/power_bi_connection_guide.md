# Power BI Connection Guide

**Status: real Power BI Project source exists, not yet opened/rendered.** [`MeridianPayExecutive.pbip`](MeridianPayExecutive.pbip) (with `MeridianPayExecutive.SemanticModel/` and `MeridianPayExecutive.Report/`) is a real Power BI Project — TMDL semantic model (all 7 tables below, the 3 relationships, and all 7 DAX measures, generated directly from the actual Gold/Silver dbt model columns, not hand-guessed) plus a 2-page report shell wired to it. It was authored as text/TMDL/JSON, not built by driving Power BI Desktop's GUI (no GUI automation available), so **it has not actually been opened in Desktop or confirmed to load/refresh against the live Databricks warehouse** — treat first-open as the remaining verification step, not a formality. If Desktop reports an error on open, that's real signal, not a false alarm — report it back and it can be fixed from there. The [live dashboard artifact](executive_dashboard.html) remains the verified, working BI deliverable regardless of how the `.pbip` opens.

**To open:** double-click `MeridianPayExecutive.pbip` in Power BI Desktop. It should prompt for Databricks OAuth sign-in (same RBAC groups as below) and load the model; the two report pages start blank — the DAX measures and star schema are already there, so building the visuals described under "Report pages" below is drag-and-drop from that point, no data modeling required.

## Connection (Databricks)

1. **Get Data → Databricks** (built-in connector, no driver install needed in recent Power BI Desktop versions).
2. Server hostname: `dbc-08add949-9c19.cloud.databricks.com`
3. HTTP path: `/sql/1.0/warehouses/59901b31d31db40a`
4. Data Connectivity mode: **DirectQuery** for the executive page (numbers should reflect the latest completed `dbt build`, not a stale import), or **Import** for the ops drill-down page if query performance on `fct_exception_queue` matters more than freshness — a hybrid composite model is the production-realistic choice.
5. Authentication: Azure AD / OAuth — sign in as a member of one of the [RBAC groups](../docs/rbac_access_matrix.md) (`recon_treasury_viewers` or `recon_bi_consumers` for a report author who shouldn't see raw Bronze/Silver).

## Connection (Snowflake, parallel-run alternative)

Same semantic model, relationships, DAX, and report pages below — only the connector and its account/role/warehouse settings change. Like the Databricks `.pbip` above, this has not been opened in Power BI Desktop in this environment (no GUI automation available) — treat first-open as the remaining verification step for this path too.

1. **Get Data → Snowflake** (built-in connector, no driver install needed in recent Power BI Desktop versions).
2. Server: `DZVUEJF-DF04786.snowflakecomputing.com` (or the account identifier form `DZVUEJF-DF04786`, depending on connector version).
3. Warehouse: `BI_WH` (deliberately separate from `TRANSFORM_WH` — see [infra_snowflake/README.md](../infra_snowflake/README.md) — so a Power BI refresh can never compete with a running `dbt build` for compute).
4. Database / schema: `MERCHANT_RECON_PROJECT_DEV` / `GOLD` (and `SILVER` for the two dimension tables).
5. Data Connectivity mode: same DirectQuery/Import split as the Databricks connection above.
6. Authentication: Snowflake supports username/password, key-pair, or SSO depending on connector version and account setup — sign in as (or map an RLS role to) one of the four [RBAC roles](../docs/rbac_access_matrix.md) (`RECON_TREASURY_VIEWERS` or `RECON_BI_CONSUMERS` for a report author who shouldn't see raw Bronze/Silver).

## Tables to import

Only Gold objects — never Bronze/Silver directly from a report tool (see [data_governance.md](../docs/data_governance.md)'s masking policy). Names below are as they appear in Databricks (lowercase); on Snowflake the identical objects are named in uppercase (`GOLD.FCT_DAILY_CASH_POSITION`, etc. — see [rbac_access_matrix.md](../docs/rbac_access_matrix.md)'s note on case folding), same columns and grain either way:

| Table | Role in the model |
|---|---|
| `gold.fct_daily_cash_position` | Fact — daily grain, drives the cash trend line and KPI cards |
| `gold.fct_reconciliation_breaks` | Fact — break-level detail, drives aging/severity visuals |
| `gold.fct_funding_cost_summary` | Fact — pre-aggregated by segment, drives the industry breakdown |
| `gold.fct_merchant_exception_trends` | Fact — merchant-level rollup, drives the drill-down table |
| `gold.vw_exception_queue_masked` | Use this instead of `fct_exception_queue` for any report shared with the BI Consumers audience |
| `silver.dim_merchant` | Dimension — industry/region/risk_tier attributes, relate on `merchant_id` |
| `silver.dim_date` | Dimension — mark as the model's official Date table (Power BI's "Mark as Date Table") |

## Relationships

- `fct_daily_cash_position[batch_date]` → `dim_date[date_day]` (many-to-one)
- `fct_reconciliation_breaks[merchant_id]` → `dim_merchant[merchant_id]` (many-to-one)
- `fct_merchant_exception_trends[merchant_id]` → `dim_merchant[merchant_id]` (one-to-one)

Star schema, not snowflake — every fact relates directly to `dim_merchant`/`dim_date`, matching how the Gold layer is already shaped (see [architecture.md](../docs/architecture.md)).

## DAX measures

Formulas mirror [kpi_contract.md](../docs/kpi_contract.md) exactly — a measure here should never define a KPI differently than that contract.

```dax
Total Expected Settlement =
SUM(fct_daily_cash_position[total_expected_settlement_amount])

Total Actual Cash Received =
SUM(fct_daily_cash_position[total_actual_cash_received])

Reconciliation Match Rate =
DIVIDE(
    SUMX(fct_daily_cash_position, fct_daily_cash_position[reconciliation_match_rate] * fct_daily_cash_position[total_expected_settlement_amount]),
    SUM(fct_daily_cash_position[total_expected_settlement_amount])
)
-- weighted average, not a naive AVERAGE() -- a straight average of daily
-- rates would over-weight low-volume days, per kpi_contract.md #8

Unresolved Break Amount (Latest Day) =
VAR LatestDate = MAX(fct_daily_cash_position[batch_date])
RETURN
    CALCULATE(
        SUM(fct_daily_cash_position[unresolved_break_amount]),
        fct_daily_cash_position[batch_date] = LatestDate
    )

Cash-at-Risk Count =
CALCULATE(
    COUNTROWS(fct_reconciliation_breaks),
    fct_reconciliation_breaks[is_cash_at_risk] = TRUE()
)

Funding Cost Estimate =
SUM(fct_reconciliation_breaks[funding_cost_estimate])

Break Rate (Dollar Basis) =
DIVIDE([Total Expected Settlement] - [Total Actual Cash Received], [Total Expected Settlement])
```

## Report pages

- **Executive KPI page**: the 4 measures above as KPI cards, `Total Expected Settlement` vs. `Total Actual Cash Received` as a line chart by `dim_date[date_day]`, break aging as a clustered bar by `fct_reconciliation_breaks[aging_bucket]`.
- **Operations drill-down page**: `Cash-at-Risk Count` and `Funding Cost Estimate` matrix by `dim_merchant[industry]` × `dim_merchant[region]`, a table visual on `fct_merchant_exception_trends` for triage, filterable by `dim_merchant[risk_tier]`.
- Both pages should carry a visible **"as of `MAX(fct_daily_cash_position[batch_date])`"** text card — DirectQuery mode makes this trivially accurate; don't hardcode a date in a text box.

## Row-level security

Power BI RLS roles should mirror the underlying warehouse's RBAC, not reinvent a parallel permission model: a `Treasury Viewer` RLS role restricted to `fct_daily_cash_position`/`fct_funding_cost_summary` only (no table access to break/merchant detail tables at all, enforced via Power BI's object-level permissions, not just row filters) matches exactly what `recon_treasury_viewers` (Databricks group) / `RECON_TREASURY_VIEWERS` (Snowflake role) gets at the warehouse — see [rbac_access_matrix.md](../docs/rbac_access_matrix.md) for both mappings.
