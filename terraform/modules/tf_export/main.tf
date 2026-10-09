terraform {
  required_version = ">= 1.16.0"
  required_providers {
    genesyscloud = {
      source = "mypurecloud/genesyscloud"
    }
  }
}

resource "genesyscloud_tf_export" "export_solution" {
  for_each = {
    for index, exp in local.export_data :
    exp.name => exp
  }
  directory               = "./export/${each.value.name}"
  include_filter_resources = ["${each.value.exp_type}"]
  include_state_file    = false
  log_permission_errors = true
  export_as_hcl         = var.export_json == false ? true : false
  split_files_by_resource = true
  use_legacy_architect_flow_exporter = false
}
