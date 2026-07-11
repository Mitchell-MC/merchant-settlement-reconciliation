# Data Governance: Masking, Lineage, and Glossary

## Masking assumptions

Merchant identity (`merchant_id`, `business_name`) is treated as sensitive commercial information once it's tied to a payment break — which specific named merchant is having settlement problems, and for how much, is not something a wide internal BI audience needs to see to do trend analysis.

| Field | Report-safe treatment | Where |
|---|---|---|
| `merchant_id` | Pseudonymized via `sha2(merchant_id, 256)` → `merchant_token` | `gold.vw_exception_queue_masked` |
| `business_name` | Dropped entirely | `gold.vw_exception_queue_masked` |
| `break_amount` | Rounded to nearest $100 | `gold.vw_exception_queue_masked` |
| `funding_cost_estimate` | Rounded to nearest $1 | `gold.vw_exception_queue_masked` |

This is implemented as a dbt view (`transform/models/gold/vw_exception_queue_masked.sql`), not a runtime access-control feature (Unity Catalog row/column-level security via dynamic views or attribute-based policies could enforce the same masking automatically for any query against the base table — scoped out here in favor of a simpler "masked view is a separate, granted object" pattern; see [rbac_access_matrix.md](rbac_access_matrix.md) for which role gets which object). A production hardening pass would move to a UC row-filter/column-mask policy so masking can't be bypassed by querying the base table directly with elevated ad-hoc permissions.

Un-masked fields (`industry`, `region`, `risk_tier`, `aging_bucket`, `severity`, dates) are not treated as sensitive — they don't identify a specific merchant.

## Lineage

Every Bronze row carries `_source_system`, `_ingestion_timestamp`, `_batch_id`, `_row_hash` (see `common/lineage.py`). This is the traceability backbone required by [non_functional_targets.md](non_functional_targets.md)'s auditability section: any Gold number can be traced back through Silver to the exact Bronze ingestion run that produced it via these columns, without needing external lineage tooling.

Unity Catalog also captures **column-level lineage automatically** for every dbt-executed SQL statement (visible in the Catalog Explorer UI or via the `system.access.table_lineage` / `system.access.column_lineage` system tables) — this is a platform capability, not something this project builds, but it's the mechanism an auditor would actually click through in a real review: pick a number in `gold.fct_daily_cash_position`, follow the lineage graph backward through `int_reconciliation_matches` → `fct_settlement_batch` / `fct_bank_movement` → `bronze.settlement_batches` / `bronze.bank_movements`.

**Manual trace path** (what the lineage graph encodes as a runbook step):
1. Gold number in question → identify which Gold model column it came from (see [kpi_contract.md](kpi_contract.md) for the formula).
2. Gold model's `ref()`/`source()` calls → walk back to the Silver models it selects from (all Silver models are thin, typed passthroughs of a single Bronze source — see any `transform/models/silver/fct_*.sql`).
3. Silver model → the Bronze source table (`transform/models/bronze/_bronze__sources.yml`).
4. Bronze row → `_batch_id` identifies the exact generator/ingestion run; `_ingestion_timestamp` gives when it landed.

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
| Root Cause Hint | `missing_posting` (no bank posting found) vs. `unmatched_closest_candidate` (amount/timing mismatch on an identified posting) | `transform/models/silver/int_reconciliation_matches.sql` |
| Severity | `critical`/`high`/`low` per exception-queue triage rule | `transform/models/gold/fct_exception_queue.sql` |

Changing any KPI's formula requires updating [kpi_contract.md](kpi_contract.md) in the same PR as the model change (see that doc's cross-cutting rules) — this glossary should never define a term differently than the contract.
