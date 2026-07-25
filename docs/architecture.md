# Architecture

## Data flow

```mermaid
flowchart TB
    subgraph Sources["Sources"]
        FRPS["FRPS workbook<br/>(Fed, triennial)"]
        CBP["CBP county file<br/>(Census, annual)"]
        CPI["CPI series<br/>(BLS API, monthly)"]
        GEN["Synthetic operational<br/>data generator<br/>(seeded, deterministic)"]
    end

    subgraph Ingest["Ingestion"]
        ING["ingestion/*.py<br/>real downloads, real parsers"]
        GENPY["data_generation/generate.py"]
    end

    FRPS --> ING
    CBP --> ING
    CPI --> ING
    GEN --> GENPY

    ING --> SFSTAGE
    GENPY --> SFSTAGE

    subgraph SFLakehouse["Snowflake — MERCHANT_RECON_PROJECT_DEV"]
        SFSTAGE[("BRONZE_LANDING<br/>internal stage, PUT + COPY INTO<br/>scripts/load_bronze_to_snowflake.py")]
        SFBRONZE[("Bronze<br/>raw, immutable, lineage metadata")]
        SFSILVER[("Silver<br/>conformed entities")]
        SFENGINE{"Reconciliation engine<br/>int_reconciliation_matches<br/>date-window + amount-tolerance"}
        SFGOLD[("Gold<br/>cash position · breaks · exception queue<br/>funding cost · merchant SLA<br/>payment mix · merchant trends")]
        SFOPS[("ops<br/>dbt_run_telemetry · run_summary")]
    end

    SFSTAGE -->|COPY INTO| SFBRONZE
    SFBRONZE -->|dbt: thin typed passthrough| SFSILVER
    SFSILVER --> SFENGINE
    SFENGINE --> SFGOLD
    SFGOLD -.->|on-run-end hook| SFOPS

    SFGOLD --> DASH["Executive / Ops dashboard<br/>(bi/executive_dashboard.html)"]
    SFGOLD --> PBI["Power BI<br/>(bi/power_bi_connection_guide.md)"]

    subgraph Governance["Governance"]
        RBAC["4 account roles<br/>engineering / finance / treasury / BI"]
        MASK["vw_exception_queue_masked<br/>sha2 pseudonymization"]
    end
    RBAC -.->|GRANT| SFBRONZE
    RBAC -.->|GRANT| SFSILVER
    RBAC -.->|GRANT| SFGOLD
    SFGOLD --> MASK

    subgraph Ops["Operate"]
        CICD["GitHub Actions<br/>ci.yml -> cd.yml -> schedule activation"]
        SFCRON["GitHub Actions<br/>snowflake_daily.yml<br/>cron-gated by repo variable"]
    end
    CICD --> SFCRON
    SFCRON -->|dbt build --target ci_snowflake| SFBRONZE

    subgraph IaC["Infrastructure as Code"]
        SFTF["Terraform (infra_snowflake/)<br/>database · schemas · warehouses<br/>roles · grants · stage · service user"]
    end
    SFTF -.->|manages| SFLakehouse
    SFTF -.->|manages| RBAC
```

## Why batch, not streaming

Settlement reconciliation is inherently a T+1/T+2 problem: you're reconciling against a bank statement that posts once a day, not a real-time event stream. Batch is the architecturally correct choice for this problem, rather than a default reached for out of habit.

## Layer responsibilities

| Layer | Owns | Materialization |
|---|---|---|
| Bronze | Raw landed data, lineage metadata (`_source_system`, `_ingestion_timestamp`, `_batch_id`, `_row_hash`) | Full-refresh table per run |
| Silver | Conformed entities, typed, 1:1 with a Bronze source (thin passthrough — no business logic) | `table` |
| Silver (engine) | `int_reconciliation_matches` — the only place matching logic lives | `table` |
| Gold | Business-facing marts, KPI-contract-exact formulas | `table` |
| ops | Observability — never business data | `table`, append-only for telemetry |

## Environments

Only `dev` (`MERCHANT_RECON_PROJECT_DEV`) is applied. `infra_snowflake/environments/prod.tfvars` parameterizes what a second environment would look like (separate database, larger warehouses) without provisioning a real duplicate footprint — see [infra_snowflake/README.md](../infra_snowflake/README.md).

## Snowflake retarget

This platform was originally built on Databricks/Unity Catalog and retargeted to Snowflake, which is now the only platform — the Databricks stack was retired on 2026-07-25. See [docs/snowflake_migration_plan.md](snowflake_migration_plan.md) for the migration plan and the non-obvious differences it surfaced (no real Bronze load mechanism existed to "redirect," Spark-only SQL that silently changes meaning on Snowflake, grants that get wiped on table rebuild).

## Where each phase's output lives

| Phase | Artifact |
|---|---|
| 1 — Business framing | [charter/PROJECT_CHARTER.md](../charter/PROJECT_CHARTER.md), [docs/kpi_contract.md](kpi_contract.md), [docs/non_functional_targets.md](non_functional_targets.md) |
| 2 — Source contracts | [docs/source_contracts/](source_contracts/), [ingestion/](../ingestion/) |
| 3 — Synthetic data | [data_generation/](../data_generation/) |
| 4 — Medallion + reconciliation | [transform/](../transform/) |
| 5 — Data quality/observability | `transform/tests/`, `gold.fct_exception_queue`, `ops.*` |
| 6 — Governance | [docs/rbac_access_matrix.md](rbac_access_matrix.md), [docs/data_governance.md](data_governance.md) |
| 7 — IaC | [infra/](../infra/) |
| 8 — CI/CD | [.github/workflows/](../.github/workflows/), [docs/release_runbook.md](release_runbook.md) |
| 9 — BI + packaging | [bi/](../bi/), this document, [docs/executive_summary.md](executive_summary.md) |
| Snowflake retarget | [infra_snowflake/](../infra_snowflake/), [docs/snowflake_migration_plan.md](snowflake_migration_plan.md), [scripts/load_bronze_to_snowflake.py](../scripts/load_bronze_to_snowflake.py) |
