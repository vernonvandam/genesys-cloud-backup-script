## OAuth Token
variable "oauthclient_id" {
  type        = string
  description = "Genesys Cloud OAuth Token ID"
}

variable "oauthclient_secret" {
  type        = string
  description = "Genesys Cloud OAuth Token Secret"
}

variable "aws_region" {
  type        = string
  default     = "ap-southeast-2"
  description = "Genesys Cloud OAuth Token Secret"
}

## Export
variable "export_json" {
  type        = bool
  description = "Export Genesys Cloud config as JSON"
  #default     = true
}
