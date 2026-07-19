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

    ING --> BRONZE
    GENPY --> BRONZE
    ING --> SFSTAGE
    GENPY --> SFSTAGE

    subgraph Lakehouse["Databricks / Unity Catalog — merchant_recon_project"]
        BRONZE[("Bronze<br/>raw, immutable, lineage metadata")]
        SILVER[("Silver<br/>conformed entities")]
        ENGINE{"Reconciliation engine<br/>int_reconciliation_matches<br/>date-window + amount-tolerance"}
        GOLD[("Gold<br/>cash position · breaks · exception queue<br/>funding cost · merchant trends")]
        OPS[("ops<br/>dbt_run_telemetry · run_summary")]
    end

    BRONZE -->|dbt: thin typed passthrough| SILVER
    SILVER --> ENGINE
    ENGINE --> GOLD
    GOLD -.->|on-run-end hook| OPS

    GOLD --> DASH["Executive / Ops dashboard<br/>(bi/executive_dashboard.html)"]
    GOLD --> PBI["Power BI<br/>(bi/power_bi_connection_guide.md)"]

    subgraph SFLakehouse["Snowflake — MERCHANT_RECON_PROJECT_DEV (parallel run)"]
        SFSTAGE[("BRONZE_LANDING<br/>internal stage, PUT + COPY INTO<br/>scripts/load_bronze_to_snowflake.py")]
        SFBRONZE[("Bronze<br/>same lineage contract")]
        SFSILVER[("Silver<br/>same conformed entities")]
        SFENGINE{"Same reconciliation engine<br/>(3 Spark-only spots rewritten<br/>via target.type Jinja)"}
        SFGOLD[("Gold<br/>same marts, same KPI formulas")]
        SFOPS[("ops<br/>same telemetry tables")]
    end

    SFSTAGE -->|COPY INTO| SFBRONZE
    SFBRONZE -->|dbt --target snowflake| SFSILVER
    SFSILVER --> SFENGINE
    SFENGINE --> SFGOLD
    SFGOLD -.->|on-run-end hook| SFOPS
    SFGOLD --> PBI

    GOLD -.->|compare by run_id / as_of_date<br/>docs/snowflake_migration_plan.md| SFGOLD

    subgraph Governance["Governance"]
        RBAC["4 RBAC groups (Databricks)<br/>4 account roles (Snowflake)<br/>engineering / finance / treasury / BI"]
        MASK["vw_exception_queue_masked<br/>sha2 pseudonymization, both platforms"]
    end
    RBAC -.->|GRANT| BRONZE
    RBAC -.->|GRANT| SILVER
    RBAC -.->|GRANT| GOLD
    RBAC -.->|GRANT| SFLakehouse
    GOLD --> MASK
    SFGOLD --> MASK

    subgraph Ops["Operate"]
        JOB["Databricks Job<br/>daily 06:00 ET, serverless<br/>paused by default"]
        CICD["GitHub Actions<br/>ci.yml -> cd.yml -> schedule activation"]
        SFCRON["GitHub Actions<br/>snowflake_daily.yml<br/>cron-gated by repo variable"]
    end
    JOB -->|dbt build| BRONZE
    CICD --> JOB
    SFCRON -->|dbt build --target snowflake| SFBRONZE

    subgraph IaC["Infrastructure as Code"]
        TF["Terraform (infra/)<br/>catalog · schemas · warehouse<br/>groups · grants · job"]
        SFTF["Terraform (infra_snowflake/)<br/>database · schemas · warehouses<br/>roles · grants · stage · service user<br/>separate state, never shares infra/'s"]
    end
    TF -.->|manages| Lakehouse
    TF -.->|manages| RBAC
    TF -.->|manages| JOB
    SFTF -.->|manages| SFLakehouse
    SFTF -.->|manages| RBAC
    SFTF -.->|manages| SFCRON
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

Only `dev` is deployed on Databricks (one live workspace). `infra/environments/prod.tfvars` parameterizes what a second environment would look like (separate catalog, larger warehouse) without provisioning a real duplicate footprint — see [infra/README.md](../infra/README.md).

The Snowflake retarget follows the identical posture: only `dev` (`MERCHANT_RECON_PROJECT_DEV`) is applied, `infra_snowflake/environments/prod.tfvars` is documented-only — see [infra_snowflake/README.md](../infra_snowflake/README.md).

## Snowflake retarget

A full second implementation of this platform on Snowflake runs in parallel with the Databricks one above — see [docs/snowflake_migration_plan.md](snowflake_migration_plan.md) for the migration plan, the non-obvious differences it surfaced (no real Bronze load mechanism existed to "redirect," Spark-only SQL that silently changes meaning on Snowflake, grants that get wiped on table rebuild), and the parallel-run/cutover checklist. `infra/` and `infra_snowflake/` are fully separate Terraform stacks with no shared state, by design.

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
