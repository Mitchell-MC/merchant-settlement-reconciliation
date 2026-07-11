{# Use the custom schema (bronze/silver/gold) exactly as configured, instead
   of dbt's default `<target_schema>_<custom_schema>` concatenation -- the
   medallion layer schemas already exist as top-level UC schemas. #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
