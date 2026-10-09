locals {

  # current_time     = timestamp()
  # local_time       = timeadd(local.current_time, "10h") # Adjust for Melbourne (UTC+10)
  # formatted_time   = replace(replace(replace(replace(local.local_time, "-", ""), ":", ""), "T", "-"), "Z", "")

  export_data = [

    {
      name          = "auth_division"
      exp_type      = "genesyscloud_auth_division"
    },
    {
      name          = "architect_user_prompt"
      exp_type      = "genesyscloud_architect_user_prompt"
    },
    {
      name          = "auth_role"
      exp_type      = "genesyscloud_auth_role"
    },
    {
      name          = "integration"
      exp_type      = "genesyscloud_integration"
    },

    {
      name          = "integration_action"
      exp_type      = "genesyscloud_integration_action"
    },
    {
      name          = "script"
      exp_type      = "genesyscloud_script"
    },
    {
      name          = "architect_datatable"
      exp_type      = "genesyscloud_architect_datatable"
    },

    {
      name          = "architect_datatable_row"
      exp_type      = "genesyscloud_architect_datatable_row"
    },
    {
      name          = "architect_ivr"
      exp_type      = "genesyscloud_architect_ivr"
    },
    {
      name          = "flow"
      exp_type      = "genesyscloud_flow"
    },
        {
      name          = "flow_milestone"
      exp_type      = "genesyscloud_flow_milestone"
    },
        {
      name          = "flow_outcome"
      exp_type      = "genesyscloud_flow_outcome"
    },
    {
      name          = "conversations_messaging_settings"
      exp_type      = "genesyscloud_conversations_messaging_settings"
    },
    # {
    #   name          = "conversations_messaging_settings_default"
    #   exp_type      = "genesyscloud_conversations_messaging_settings_default"
    # },
    {
      name          = "conversations_settings"
      exp_type      = "genesyscloud_conversations_settings"
    },
    # {
    #   name          = "telephony_providers_edges_did_pool"
    #   exp_type      = "genesyscloud_telephony_providers_edges_did_pool"
    # },

  ]
}
