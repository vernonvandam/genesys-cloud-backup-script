terraform {
  required_version = ">= 1.16.0"
  required_providers {
    genesyscloud = {
      source = "mypurecloud/genesyscloud"
    }
  }
}

provider "genesyscloud" {
  oauthclient_id     = var.oauthclient_id
  oauthclient_secret = var.oauthclient_secret
  aws_region         = var.aws_region
}

module "tf_export" {
  # Done
  source      = "./modules/tf_export"
  export_json = var.export_json
}
