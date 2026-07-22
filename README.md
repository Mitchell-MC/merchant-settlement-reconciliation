# Merchant Settlement Reconciliation & Cash Visibility

A production-styled reconciliation platform for a fictional SMB payment facilitator ("Meridian Pay"). It matches expected merchant settlement obligations against actual bank cash movement, surfaces unresolved breaks and their aging, and gives finance/treasury daily, auditable cash visibility. It runs on **Databricks** (primary) and is **retargeted to Snowflake** as a verified parallel platform.

This is a **batch reconciliation** platform, a deliberate architectural choice rather than a default: settlement reconciles against a bank statement that posts once a day, so there's no real-time version of "did the money move." The design demonstrates when batch is the architecturally correct answer, instead of defaulting to streaming for every problem.

## Why this exists

Anyone who processes third-party payouts — payment facilitators, marketplaces, gig platforms — has to answer one question every day: *did the money that was supposed to move actually move, and if not, why not, and how much is at risk?* This project builds that capability end-to-end: business framing → data contracts → synthetic operational data → medallion lakehouse → reconciliation engine → data-quality gates → governance → IaC → CI/CD → executive BI — plus the operational layer that makes it trustworthy in production: observability, silent-failure detection, and incident response.

See [charter/PROJECT_CHARTER.md](charter/PROJECT_CHARTER.md) for the full business framing, stakeholder map, and interview narratives.

## Architecture at a glance

```
FRPS / CBP / CPI / FRED (public macro reference data)     Synthetic operational data generator
        |                                                    |
        v                                                    v
                    Bronze  (raw landed, immutable, lineage metadata)
                              |   ← boundary data-contract validation alerts on type/shape drift
                    Silver  (conformed entities: merchant, settlement batch,
                              payment channel, bank movement, date)
                              |
                    Reconciliation engine  (date-window + amount-tolerance matching)
                              |
                    Gold    (cash position, breaks, aging, root cause, funding cost —
                              star schema)
                              |
                    Executive dashboard (live) + Power BI (documented)

         ops schema (sidecar): run telemetry · daily run_summary · pipeline heartbeat
```

Same dbt models run on **Databricks** (Unity Catalog on AWS) and **Snowflake** via `--target`, with engine differences handled behind `{% if target.type == 'snowflake' %}` branches. See [docs/architecture.md](docs/architecture.md) for the full data-flow diagram and [docs/snowflake_migration_plan.md](docs/snowflake_migration_plan.md) for the retarget. The executive dashboard ([source](bi/executive_dashboard.html)) is built from real Gold-layer data and published as a private Claude artifact — share it from claude.ai/code/artifacts before sending the link to anyone else.

## Production-readiness & operations

The controls that separate a working pipeline from a trustworthy one:

- **CI gate** ([.github/workflows/ci.yml](.github/workflows/ci.yml)) — runs on every push/PR: `ruff` lint, `pytest` with a coverage ratchet (`--cov-fail-under`, config in [pyproject.toml](pyproject.toml)), `terraform validate`, and `dbt parse`. A live `dbt build` against the dev catalog runs on PRs.
- **CD** ([.github/workflows/cd.yml](.github/workflows/cd.yml)) — deploys the dbt project to the workspace (`databricks sync` + a `dbt build` smoke test) behind a two-part gate (`CD_DEPLOY_ENABLED` + service-principal secrets) and a required-reviewer approval before the daily schedule is activated. Infrastructure is applied via Terraform **separately** (state is local, not in CI) — a deliberate scope, see [cd.yml](.github/workflows/cd.yml) header.
- **Silent-failure detection** — source freshness is a pre-build gate (stale/missing operational data fails loudly instead of publishing green Gold on old data); a **dead-man's-switch** ([transform/tests/assert_pipeline_not_silent.sql](transform/tests/assert_pipeline_not_silent.sql)) runs on its own independent schedule and alerts when the pipeline stops running at all — the one check a pipeline can't do on itself. Health rolls up to `ops.run_summary` / `ops.pipeline_heartbeat`.
- **Incident response** — [docs/incident_runbook.md](docs/incident_runbook.md) (a four-fronts playbook: blast radius → containment → stakeholder comms → system verdict) and [docs/release_runbook.md](docs/release_runbook.md) (release checklist, rollback, backfill).
- **Fail loud, not silent** — structured logging ([common/logging_setup.py](common/logging_setup.py)) over `print()`; a boundary data-contract check ([common/validation.py](common/validation.py)) that fires a CRITICAL alert (naming the offending value) when a numeric column arrives as strings or a required column vanishes, before it lands in Bronze.

## Repo layout

| Path | Contents |
|---|---|
| [charter/](charter/) | Business framing, stakeholder map, scope, interview narratives |
| [docs/](docs/) | KPI contract, non-functional targets & SLAs, source contracts, governance/RBAC, architecture, **incident & release runbooks**, **Snowflake migration plan** |
| [data_generation/](data_generation/) | Deterministic synthetic operational data generator |
| [ingestion/](ingestion/) | FRPS / CBP / CPI / FRED macro reference data ingestion scripts |
| [common/](common/) | Shared Bronze lineage/landing helpers, structured logging, and boundary data-contract validation |
| [transform/](transform/) | dbt project — Bronze/Silver/Gold models, reconciliation logic, tests, and the `ops` observability models; runs on Databricks or Snowflake via `--target` |
| [infra/](infra/) | Terraform (Databricks) — Unity Catalog, warehouse, RBAC groups/grants, the daily reconciliation job, and the independent heartbeat job |
| [infra_snowflake/](infra_snowflake/) | Terraform (Snowflake) — parallel database, warehouses, roles/grants, service user, stage |
| [.github/workflows/](.github/workflows/) | CI, CD, and the Snowflake daily + heartbeat workflows; `.github/ci*/` hold the CI-only dbt profiles |
| [bi/](bi/) | Executive dashboard (live, real data) and `MeridianPayExecutive.pbip` Power BI project (TMDL semantic model + report shell — see [bi/power_bi_connection_guide.md](bi/power_bi_connection_guide.md) for status) |
| [scripts/](scripts/) | Operational scripts (segment-weight derivation, workspace sync, Snowflake Bronze load) |
| [tests/](tests/) | Pytest unit tests for `data_generation/`, `ingestion/`, and `common/` — holiday/business-day math, lineage hashing, weight sanity, response parsing, and data-contract validation (fail-on-bad-data) |

## Status

All 9 build phases are complete, and the operational layer above (CI green, CD live behind an approval gate, Snowflake parity, observability + incident tooling) is in place. See [docs/executive_summary.md](docs/executive_summary.md) for a one-page summary and [docs/architecture.md](docs/architecture.md) for where each phase's output lives.

## Scope boundaries

**In:** daily batch reconciliation, synthetic operational data derived from public sources, dual-platform (Databricks + Snowflake), production-readiness controls (CI/CD, observability, incident response).
**Out:** real confidential processor/bank feeds, full enterprise IAM federation, remote Terraform state / automated infra apply in CI, true real-time stream processing (see the companion streaming project for that).
