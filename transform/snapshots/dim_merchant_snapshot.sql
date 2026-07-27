{#-
    SCD2 history for merchant attributes that change over the merchant's
    lifecycle but that dim_merchant (Silver) only ever exposes as-of "now":
    risk_tier, fee/reserve rates, and settlement speed are contract terms
    Treasury/Controller re-price over time, not fixed reference data. Without
    this, a re-join from fct_reconciliation_breaks to dim_merchant always
    resolves to the CURRENT tier/rate, so "what was this merchant's risk
    tier when this break happened in March" cannot be answered once the
    tier has since changed -- see docs/kpi_contract.md's Controller/Treasury
    KPI owners, who are exactly the stakeholders who ask that question.

    Sourced from Bronze (not Silver's dim_merchant) because dim_merchant is a
    plain passthrough with no transformation -- snapshotting the source
    directly avoids adding a dependency on a model that adds no value for
    this purpose, and matches dbt's own guidance to snapshot as close to the
    source as possible.

    strategy='check' (not 'timestamp'): Bronze's merchants table is a full
    per-run overwrite with a fresh _ingestion_timestamp on every row every
    run (see common/lineage.py), including rows whose business attributes
    did NOT change -- a timestamp strategy would treat every single run as a
    change and version every merchant every day. check_cols against the
    actual mutable business columns is what makes "changed" mean "the
    contract terms actually changed," not "the pipeline ran again."
#}

{% snapshot dim_merchant_snapshot %}

{{
    config(
        target_schema='snapshots',
        unique_key='merchant_id',
        strategy='check',
        check_cols=[
            'risk_tier',
            'reserve_rate_bps',
            'processing_fee_bps',
            'settlement_speed_business_days',
        ],
    )
}}

select
    merchant_id,
    business_name,
    industry,
    mcc,
    region,
    state,
    employer_size_class,
    risk_tier,
    onboarding_date,
    reserve_rate_bps,
    processing_fee_bps,
    settlement_speed_business_days,
    avg_ticket_usd,
    _source_system,
    _ingestion_timestamp,
    _batch_id
from {{ source('bronze', 'merchants') }}

{% endsnapshot %}
