# Merchant Settlement Reconciliation & Cash Visibility

A production-styled, Databricks-based reconciliation platform for a fictional SMB payment facilitator ("Meridian Pay"). It matches expected merchant settlement obligations against actual bank cash movement, surfaces unresolved breaks and their aging, and gives finance/treasury daily, auditable cash visibility.

This is the **batch reconciliation** half of a two-project fintech data engineering portfolio. The companion project, [Fintech_project](../Fintech_project), is the **real-time streaming** half (fraud/AML detection). Together they demonstrate after-the-fact financial audit versus real-time defense — the two core patterns in fintech data engineering.

## Why this exists

Anyone who processes third-party payouts — payment facilitators, marketplaces, gig platforms — has to answer one question every day: *did the money that was supposed to move actually move, and if not, why not, and how much is at risk?* This project builds that capability end-to-end: business framing → data contracts → synthetic operational data → medallion lakehouse → reconciliation engine → data quality gates → governance → IaC → CI/CD → executive BI.

See [charter/PROJECT_CHARTER.md](charter/PROJECT_CHARTER.md) for the full business framing, stakeholder map, and interview narratives.

## Architecture at a glance

```
FRPS / CBP / CPI (public macro reference data)     Synthetic operational data generator
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
                    Power BI  (executive KPI page + ops drill-down)
```

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
| [bi/](bi/) | Power BI model docs, KPI traceability page |
| [scripts/](scripts/) | Operational scripts (segment-weight derivation, workspace sync) |

## Status

Build tracked against a 9-phase, 10-week plan. Currently in Phases 1–4 (business framing, source contracts, synthetic data generation, medallion modeling + reconciliation engine).

## Scope boundaries

**In:** daily batch reconciliation, synthetic operational data derived from public sources, production-readiness controls.
**Out:** real confidential processor/bank feeds, full enterprise IAM federation, true real-time stream processing (see the companion streaming project for that).
