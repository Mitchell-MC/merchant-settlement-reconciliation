# databricks_grants is authoritative per securable (it overwrites, not
# appends) -- one resource per catalog/schema/table, each listing every
# principal that should have access. Table/view-level grants reference
# Gold objects by name rather than a Terraform resource, since dbt (not
# Terraform) owns table/view DDL -- a deliberate split of responsibility,
# not an oversight.

resource "databricks_grants" "catalog" {
  provider = databricks.workspace
  catalog  = databricks_catalog.this.name

  grant {
    principal  = databricks_group.engineering.display_name
    privileges = ["ALL_PRIVILEGES"]
  }
  grant {
    principal  = databricks_group.treasury_viewers.display_name
    privileges = ["USE_CATALOG"]
  }
  grant {
    principal  = databricks_group.finance_analysts.display_name
    privileges = ["USE_CATALOG"]
  }
  grant {
    principal  = databricks_group.bi_consumers.display_name
    privileges = ["USE_CATALOG"]
  }
}

resource "databricks_grants" "silver_schema" {
  provider = databricks.workspace
  schema   = "${databricks_catalog.this.name}.${databricks_schema.silver.name}"

  grant {
    principal  = databricks_group.finance_analysts.display_name
    privileges = ["USE_SCHEMA", "SELECT"]
  }
}

resource "databricks_grants" "gold_schema" {
  provider = databricks.workspace
  schema   = "${databricks_catalog.this.name}.${databricks_schema.gold.name}"

  grant {
    principal  = databricks_group.finance_analysts.display_name
    privileges = ["USE_SCHEMA", "SELECT"]
  }
  grant {
    principal  = databricks_group.treasury_viewers.display_name
    privileges = ["USE_SCHEMA"]
  }
  grant {
    principal  = databricks_group.bi_consumers.display_name
    privileges = ["USE_SCHEMA"]
  }
}

resource "databricks_grants" "cash_position_table" {
  provider = databricks.workspace
  table    = "${databricks_catalog.this.name}.${databricks_schema.gold.name}.fct_daily_cash_position"

  grant {
    principal  = databricks_group.treasury_viewers.display_name
    privileges = ["SELECT"]
  }
  grant {
    principal  = databricks_group.bi_consumers.display_name
    privileges = ["SELECT"]
  }
}

resource "databricks_grants" "funding_cost_table" {
  provider = databricks.workspace
  table    = "${databricks_catalog.this.name}.${databricks_schema.gold.name}.fct_funding_cost_summary"

  grant {
    principal  = databricks_group.treasury_viewers.display_name
    privileges = ["SELECT"]
  }
  grant {
    principal  = databricks_group.bi_consumers.display_name
    privileges = ["SELECT"]
  }
}

resource "databricks_grants" "masked_exception_view" {
  provider = databricks.workspace
  table    = "${databricks_catalog.this.name}.${databricks_schema.gold.name}.vw_exception_queue_masked"

  grant {
    principal  = databricks_group.bi_consumers.display_name
    privileges = ["SELECT"]
  }
}
