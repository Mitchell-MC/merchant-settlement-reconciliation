{# Observability (Phase 5): after every dbt invocation, log each node's
   outcome to ops.dbt_run_telemetry -- run status, timing, and row counts
   per model/test/seed. This is what "publish telemetry: run status, row
   counts, test outcomes" means in practice: a queryable table, not a log
   file nobody reads. #}

{% macro create_run_telemetry_table() %}
    {% set ddl %}
        create table if not exists {{ target.database }}.ops.dbt_run_telemetry (
            invocation_id string,
            run_started_at timestamp,
            node_name string,
            node_resource_type string,
            status string,
            execution_time_seconds double,
            rows_affected bigint,
            message string
        )
    {% endset %}
    {% do run_query(ddl) %}
{% endmacro %}

{% macro log_run_results(results) %}
    {% if execute and results | length > 0 %}
        {{ create_run_telemetry_table() }}
        {% set value_rows = [] %}
        {% for r in results %}
            {% set node = r.node %}
            {% set rows_affected = none %}
            {% if r.adapter_response and r.adapter_response.get('rows_affected') is not none %}
                {% set rows_affected = r.adapter_response.get('rows_affected') %}
            {% endif %}
            {% set message = (r.message or '') | replace("'", "''") | truncate(500) %}
            {% set node_name = node.name | replace("'", "''") %}
            {% do value_rows.append(
                "('" ~ invocation_id ~ "', current_timestamp(), '" ~ node_name ~ "', '" ~ node.resource_type
                ~ "', '" ~ r.status ~ "', " ~ r.execution_time ~ ", "
                ~ (rows_affected if rows_affected is not none else 'NULL') ~ ", '" ~ message ~ "')"
            ) %}
        {% endfor %}
        {% set insert_sql %}
            insert into {{ target.database }}.ops.dbt_run_telemetry
            (invocation_id, run_started_at, node_name, node_resource_type, status, execution_time_seconds, rows_affected, message)
            values {{ value_rows | join(', ') }}
        {% endset %}
        {% do run_query(insert_sql) %}
    {% endif %}
{% endmacro %}
