# Snowflake equivalent of infra/grants.tf's matrix. Snowflake's grant
# model is role-centric (one resource per role+privilege+object) rather
# than securable-centric like databricks_grants, but the resulting
# access matrix is identical -- see docs/rbac_access_matrix.md.
#
# One addition with no Databricks equivalent: Snowflake requires
# explicit warehouse USAGE grants for a role to run any query at all
# (Databricks SQL warehouse access wasn't Terraform-managed here). Those
# are grouped at the top since every other grant is meaningless without
# them.
#
# ORDERING CAVEAT: the specific-table/view grants below (cash position,
# funding cost, masked exception view) name Gold objects that don't
# exist until dbt has built them at least once -- same "dbt owns DDL"
# split as the Databricks stack. On a from-scratch environment, apply
# this stack once with those four resources commented out (or targeted
# out via -target), run `dbt build --target snowflake`, then apply again
# for the full matrix. See infra_snowflake/README.md.

# --- Warehouse usage ---

resource "snowflake_grant_privileges_to_account_role" "engineering_transform_wh_usage" {
  account_role_name = snowflake_account_role.engineering.name
  privileges = ["USAGE", "OPERATE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.transform.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "finance_analysts_bi_wh_usage" {
  account_role_name = snowflake_account_role.finance_analysts.name
  privileges = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.bi.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "treasury_viewers_bi_wh_usage" {
  account_role_name = snowflake_account_role.treasury_viewers.name
  privileges = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.bi.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "bi_consumers_bi_wh_usage" {
  account_role_name = snowflake_account_role.bi_consumers.name
  privileges = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.bi.name
  }
}

# --- Schema level: ENGINEERING needs explicit schema-level privileges
# even though it already has database-level ALL PRIVILEGES above --
# unlike Unity Catalog, Snowflake's database-level ALL PRIVILEGES does
# NOT cascade to schema-level capabilities (CREATE TABLE/VIEW/STAGE,
# etc.) or to objects that predate the grant. Whatever RECON_ENGINEERING
# creates via dbt it will own outright (owner privileges are automatic),
# so this schema-level grant -- not per-object grants -- is all
# engineering needs to build and fully manage the pipeline. ---

resource "snowflake_grant_privileges_to_account_role" "engineering_bronze_schema_all" {
  account_role_name = snowflake_account_role.engineering.name
  all_privileges     = true
  on_schema {
    schema_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.bronze.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineering_silver_schema_all" {
  account_role_name = snowflake_account_role.engineering.name
  all_privileges     = true
  on_schema {
    schema_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.silver.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineering_gold_schema_all" {
  account_role_name = snowflake_account_role.engineering.name
  all_privileges     = true
  on_schema {
    schema_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.gold.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineering_ops_schema_all" {
  account_role_name = snowflake_account_role.engineering.name
  all_privileges     = true
  on_schema {
    schema_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.ops.name}\""
  }
}

# The Bronze landing stage and its file format are created by this
# Terraform config's own (ACCOUNTADMIN) identity, not by RECON_ENGINEERING
# -- ownership doesn't transfer just because engineering has schema-level
# ALL PRIVILEGES, so PUT/COPY INTO against the stage need an explicit grant.
resource "snowflake_grant_privileges_to_account_role" "engineering_bronze_stage_rw" {
  account_role_name = snowflake_account_role.engineering.name
  privileges         = ["READ", "WRITE"]
  on_schema_object {
    object_type = "STAGE"
    object_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.bronze.name}\".\"${snowflake_stage.bronze_landing.name}\""
  }
}

# --- Database level ---

resource "snowflake_grant_privileges_to_account_role" "engineering_database_all" {
  account_role_name = snowflake_account_role.engineering.name
  privileges = ["ALL PRIVILEGES"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.this.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "treasury_viewers_database_usage" {
  account_role_name = snowflake_account_role.treasury_viewers.name
  privileges = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.this.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "finance_analysts_database_usage" {
  account_role_name = snowflake_account_role.finance_analysts.name
  privileges = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.this.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "bi_consumers_database_usage" {
  account_role_name = snowflake_account_role.bi_consumers.name
  privileges = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.this.name
  }
}

# --- Schema level: SILVER (finance_analysts only, mirrors infra/grants.tf) ---

resource "snowflake_grant_privileges_to_account_role" "finance_analysts_silver_usage" {
  account_role_name = snowflake_account_role.finance_analysts.name
  privileges = ["USAGE"]
  on_schema {
    schema_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.silver.name}\""
  }
}

# SELECT on all existing + all future Silver tables reproduces
# Databricks' schema-level SELECT, which cascades to every table
# automatically -- Snowflake needs both an ALL grant (current objects)
# and a FUTURE grant (objects dbt creates later) to get the same effect.
resource "snowflake_grant_privileges_to_account_role" "finance_analysts_silver_select_existing" {
  account_role_name = snowflake_account_role.finance_analysts.name
  privileges = ["SELECT"]
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema           = "\"${snowflake_database.this.name}\".\"${snowflake_schema.silver.name}\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "finance_analysts_silver_select_future" {
  account_role_name = snowflake_account_role.finance_analysts.name
  privileges = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema           = "\"${snowflake_database.this.name}\".\"${snowflake_schema.silver.name}\""
    }
  }
}

# --- Schema level: GOLD ---

resource "snowflake_grant_privileges_to_account_role" "finance_analysts_gold_usage" {
  account_role_name = snowflake_account_role.finance_analysts.name
  privileges = ["USAGE"]
  on_schema {
    schema_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.gold.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "finance_analysts_gold_select_existing" {
  account_role_name = snowflake_account_role.finance_analysts.name
  privileges = ["SELECT"]
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema           = "\"${snowflake_database.this.name}\".\"${snowflake_schema.gold.name}\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "finance_analysts_gold_select_future" {
  account_role_name = snowflake_account_role.finance_analysts.name
  privileges = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema           = "\"${snowflake_database.this.name}\".\"${snowflake_schema.gold.name}\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "treasury_viewers_gold_usage" {
  account_role_name = snowflake_account_role.treasury_viewers.name
  privileges = ["USAGE"]
  on_schema {
    schema_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.gold.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "bi_consumers_gold_usage" {
  account_role_name = snowflake_account_role.bi_consumers.name
  privileges = ["USAGE"]
  on_schema {
    schema_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.gold.name}\""
  }
}

# --- Named-object level: only these two marts are readable by
# treasury/bi_consumers (no blanket Gold SELECT for them, matching
# infra/grants.tf's cash_position_table / funding_cost_table) ---

resource "snowflake_grant_privileges_to_account_role" "treasury_viewers_cash_position_select" {
  account_role_name = snowflake_account_role.treasury_viewers.name
  privileges = ["SELECT"]
  on_schema_object {
    object_type = "TABLE"
    object_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.gold.name}\".\"FCT_DAILY_CASH_POSITION\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "bi_consumers_cash_position_select" {
  account_role_name = snowflake_account_role.bi_consumers.name
  privileges = ["SELECT"]
  on_schema_object {
    object_type = "TABLE"
    object_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.gold.name}\".\"FCT_DAILY_CASH_POSITION\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "treasury_viewers_funding_cost_select" {
  account_role_name = snowflake_account_role.treasury_viewers.name
  privileges = ["SELECT"]
  on_schema_object {
    object_type = "TABLE"
    object_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.gold.name}\".\"FCT_FUNDING_COST_SUMMARY\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "bi_consumers_funding_cost_select" {
  account_role_name = snowflake_account_role.bi_consumers.name
  privileges = ["SELECT"]
  on_schema_object {
    object_type = "TABLE"
    object_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.gold.name}\".\"FCT_FUNDING_COST_SUMMARY\""
  }
}

# Masked exception queue view -- BI_CONSUMERS only, matching
# infra/grants.tf's masked_exception_view (never granted to
# treasury_viewers or finance_analysts).
resource "snowflake_grant_privileges_to_account_role" "bi_consumers_masked_view_select" {
  account_role_name = snowflake_account_role.bi_consumers.name
  privileges = ["SELECT"]
  on_schema_object {
    object_type = "VIEW"
    object_name = "\"${snowflake_database.this.name}\".\"${snowflake_schema.gold.name}\".\"VW_EXCEPTION_QUEUE_MASKED\""
  }
}
