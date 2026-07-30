# Data Governance: Masking, Lineage, and Glossary

**Snowflake is the live platform** (Databricks was retired 2026-07-25 — see [snowflake_migration_plan.md](snowflake_migration_plan.md)). The masking/lineage mechanisms below that reference Unity Catalog are kept as the original design reasoning; the "production hardening" and "automatic lineage" notes point to their Snowflake equivalents where noted.

## Masking assumptions

Merchant identity (`merchant_id`, `business_name`) is treated as sensitive commercial information once it's tied to a payment break — which specific named merchant is having settlement problems, and for how much, is not something a wide internal BI audience needs to see to do trend analysis.

| Field | Report-safe treatment | Where |
|---|---|---|
| `merchant_id` | Pseudonymized via `sha2(merchant_id, 256)` → `merchant_token` | `gold.vw_exception_queue_masked` |
| `business_name` | Dropped entirely | `gold.vw_exception_queue_masked` |
| `break_amount` | Rounded to nearest $100 | `gold.vw_exception_queue_masked` |
| `funding_cost_estimate` | Rounded to nearest $1 | `gold.vw_exception_queue_masked` |

This is implemented as a dbt view (`transform/models/gold/vw_exception_queue_masked.sql`), not a runtime access-control feature — Unity Catalog row/column-level security (dynamic views or attribute-based policies) and Snowflake's equivalent (row access policies / masking policies) could both enforce the same masking automatically for any query against the base table; scoped out here in favor of a simpler "masked view is a separate, granted object" pattern (see [rbac_access_matrix.md](rbac_access_matrix.md) for which role gets which object). A production hardening pass on the live Snowflake platform would move to a Snowflake masking policy attached directly to `gold.fct_exception_queue`'s sensitive columns, so masking can't be bypassed by querying the base table directly with elevated ad-hoc permissions.

Un-masked fields (`industry`, `region`, `risk_tier`, `aging_bucket`, `severity`, dates) are not treated as sensitive — they don't identify a specific merchant.

## Lineage

Every Bronze row carries `_source_system`, `_ingestion_timestamp`, `_batch_id`, `_row_hash` (see `common/lineage.py`). This is the traceability backbone required by [non_functional_targets.md](non_functional_targets.md)'s auditability section: any Gold number can be traced back through Silver to the exact Bronze ingestion run that produced it via these columns, without needing external lineage tooling.

On the live Snowflake platform, **`ACCESS_HISTORY` and `OBJECT_DEPENDENCIES`** (Account Usage schema views) capture object-level read/write lineage automatically for every query, including dbt's — the mechanism an auditor would actually click through in a real review today: pick a number in `gold.fct_daily_cash_position`, follow the lineage graph backward through `int_reconciliation_matches` → `fct_settlement_batch` / `fct_bank_movement` → `bronze.settlement_batches` / `bronze.bank_movements`. This is a platform capability, not something this project builds. (During the Databricks era, the equivalent was Unity Catalog's automatic column-level lineage via the Catalog Explorer UI or the `system.access.table_lineage` / `system.access.column_lineage` system tables — kept here as the original design reference, since the same manual trace path below applies on either platform.)

**Manual trace path** (what the lineage graph encodes as a runbook step):
1. Gold number in question → identify which Gold model column it came from (see [kpi_contract.md](kpi_contract.md) for the formula).
2. Gold model's `ref()`/`source()` calls → walk back to the Silver models it selects from (all Silver models are thin, typed passthroughs of a single Bronze source — see any `transform/models/silver/fct_*.sql`).
3. Silver model → the Bronze source table (`transform/models/bronze/_bronze__sources.yml`).
4. Bronze row → `_batch_id` identifies the exact generator/ingestion run; `_ingestion_timestamp` gives when it landed.

**Point-in-time correctness.** `dim_merchant` is current-state-only, so a merchant re-tiered after a break occurred would otherwise have that break silently reclassified under the new tier on every rebuild. A dbt snapshot (`transform/snapshots/dim_merchant_snapshot.sql`) captures SCD2 history on the mutable contract-term columns, and `fct_reconciliation_breaks` resolves `risk_tier` as-of `break_first_identified_date` rather than off current-state `dim_merchant` — an auditor re-running the trace path above against a historical break sees the tier that was true then, not today's.

## Business glossary (KPI-critical Gold metrics)

The authoritative definitions live in [kpi_contract.md](kpi_contract.md) — this is a quick-reference index into it, the form an auditor or new analyst would actually want first.

| Term | One-line definition | Full definition |
|---|---|---|
| Expected Settlement Amount | What the ledger says a merchant is owed for a batch | [kpi_contract.md #1](kpi_contract.md#1-expected-settlement-amount) |
| Actual Cash Received | What the bank actually posted, matched to a batch | [kpi_contract.md #2](kpi_contract.md#2-actual-cash-received) |
| Unresolved Break Amount | Dollar gap between expected and actual, still open | [kpi_contract.md #3](kpi_contract.md#3-unresolved-break-amount) |
| Break Rate | Breaks as a share of total batches (count or $) | [kpi_contract.md #4](kpi_contract.md#4-break-rate) |
| Break Aging | Business days a break has sat unresolved, bucketed | [kpi_contract.md #5](kpi_contract.md#5-break-aging) |
| Cash-at-Risk | Break $ aged beyond the SLA threshold (5 business days) | [kpi_contract.md #6](kpi_contract.md#6-cash-at-risk) |
| Funding Cost Estimate | Estimated cost of capital tied up by open breaks | [kpi_contract.md #7](kpi_contract.md#7-funding-cost-estimate) |
| Reconciliation Match Rate | Straight-through rate — the engine's own health metric | [kpi_contract.md #8](kpi_contract.md#8-reconciliation-match-rate-straight-through-rate) |
| Aging Bucket | `0-1`, `2-3`, `4-7`, `8-14`, `15+` business days | [kpi_contract.md #5](kpi_contract.md#5-break-aging) |
| Root Cause Hint | `delayed` (in-tolerance posting arrived after the window), `unmatched_closest_candidate` (amount/timing mismatch on an identified posting), or `missing_posting` (no candidate posting found) | [kpi_contract.md — root cause hint](kpi_contract.md#root-cause-hint-break-triage-classification) |
| Severity | `critical`/`high`/`medium`/`low` per exception-queue triage rule (`fct_duplicate_posting_exceptions` uses a `critical`/`high` split on the same $5,000 threshold) | `transform/models/gold/fct_exception_queue.sql`, `transform/models/gold/fct_duplicate_posting_exceptions.sql` |
| Duplicate Posting Exposure | Bank postings that duplicate an already-claimed posting — real cash posted twice | [kpi_contract.md #9](kpi_contract.md#9-duplicate-posting-exposure) |

Changing any KPI's formula requires updating [kpi_contract.md](kpi_contract.md) in the same PR as the model change (see that doc's cross-cutting rules) — this glossary should never define a term differently than the contract.
