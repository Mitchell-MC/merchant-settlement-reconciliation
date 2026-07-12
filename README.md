# Merchant Settlement Reconciliation & Cash Visibility

A production-styled, Databricks-based reconciliation platform for a fictional SMB payment facilitator ("Meridian Pay"). It matches expected merchant settlement obligations against actual bank cash movement, surfaces unresolved breaks and their aging, and gives finance/treasury daily, auditable cash visibility.

This is a **batch reconciliation** platform, a deliberate architectural choice rather than a default: settlement reconciles against a bank statement that posts once a day, so there's no real-time version of "did the money move." The design demonstrates when batch is the architecturally correct answer, instead of defaulting to streaming for every problem.

## Why this exists

Anyone who processes third-party payouts — payment facilitators, marketplaces, gig platforms — has to answer one question every day: *did the money that was supposed to move actually move, and if not, why not, and how much is at risk?* This project builds that capability end-to-end: business framing → data contracts → synthetic operational data → medallion lakehouse → reconciliation engine → data quality gates → governance → IaC → CI/CD → executive BI.

See [charter/PROJECT_CHARTER.md](charter/PROJECT_CHARTER.md) for the full business framing, stakeholder map, and interview narratives.

## Architecture at a glance

```
FRPS / CBP / CPI / FRED (public macro reference data)     Synthetic operational data generator
        |                                                    |
        v                                                    v
                    Bronze  (raw landed, immutable, lineage metadata)
                              |
                    Silver  (conformed entities: merchant, settlement batch,
                              payment channel, bank movement, date)
                              |
                    Reconciliation engine  (date-window + amount-tolerance matching)
                              |
                    Gold    (cash position, breaks, aging, root cause, funding cost —
                              star schema)
                              |
                    Executive dashboard (live) + Power BI (documented)
```

See [docs/architecture.md](docs/architecture.md) for the full data-flow diagram. The executive dashboard ([source](bi/executive_dashboard.html)) is built from real Gold-layer data and published as a private Claude artifact — share it from claude.ai/code/artifacts before sending the link to anyone else.

Runs on Databricks (Unity Catalog, AWS). Infrastructure is Terraform-managed; transformations are tested dbt models; CI/CD gates deployment on SQL/dbt validation, test execution, and Terraform plan.

## Repo layout

| Path | Contents |
|---|---|
| [charter/](charter/) | Business framing, stakeholder map, scope, interview narratives |
| [docs/](docs/) | KPI contract, non-functional targets, source ingestion contracts, glossary, RBAC/access matrix |
| [data_generation/](data_generation/) | Deterministic synthetic operational data generator |
| [ingestion/](ingestion/) | FRPS/CBP/CPI macro reference data ingestion scripts |
| [common/](common/) | Shared Bronze lineage/landing helpers used by both `data_generation/` and `ingestion/` |
| [transform/](transform/) | dbt-databricks project — Bronze/Silver/Gold models, tests, reconciliation logic |
| [infra/](infra/) | Terraform — Unity Catalog, warehouse, RBAC groups/grants, the daily reconciliation job |
| [.github/workflows/](.github/workflows/) | CI (`ci.yml`) and CD (`cd.yml`) pipelines; `.github/ci/` holds the CI-only dbt profile |
| [bi/](bi/) | Executive dashboard (live, real data); `MeridianPayExecutive.pbip` Power BI Project (real TMDL semantic model + report shell, not yet opened in Desktop — see [bi/power_bi_connection_guide.md](bi/power_bi_connection_guide.md) for status) |
| [scripts/](scripts/) | Operational scripts (segment-weight derivation, workspace sync) |
| [tests/](tests/) | Pytest unit tests for `data_generation/`, `ingestion/`, and `common/` (holiday/business-day math, lineage hashing, weight sanity checks, response parsing) |

## Status

All 9 phases complete. See [docs/executive_summary.md](docs/executive_summary.md) for a one-page summary, [docs/architecture.md](docs/architecture.md) for where each phase's output lives, and [docs/interview_prep.md](docs/interview_prep.md) for design-tradeoff talking points and real bugs found/fixed during the build.

## Scope boundaries

**In:** daily batch reconciliation, synthetic operational data derived from public sources, production-readiness controls.
**Out:** real confidential processor/bank feeds, full enterprise IAM federation, true real-time stream processing (see the companion streaming project for that).
