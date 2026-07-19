output "database_name" {
  value = snowflake_database.this.name
}

output "transform_warehouse_name" {
  value = snowflake_warehouse.transform.name
}

output "bi_warehouse_name" {
  value = snowflake_warehouse.bi.name
}

output "rbac_role_names" {
  value = {
    engineering      = snowflake_account_role.engineering.name
    treasury_viewers = snowflake_account_role.treasury_viewers.name
    finance_analysts = snowflake_account_role.finance_analysts.name
    bi_consumers     = snowflake_account_role.bi_consumers.name
  }
}

output "ci_cd_service_user" {
  value = snowflake_service_user.ci_cd.name
}
