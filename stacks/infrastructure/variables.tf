variable "aws_account_id" {
  description = "The infrastructure account id. Guardrail via allowed_account_ids."
  type        = string
}

variable "org_id" {
  description = "AWS Organizations id (o-xxxx). Scopes who may assume the dns-delegation role."
  type        = string
}

variable "parent_zone_name" {
  description = "The shared parent DNS zone this account owns, e.g. ecolors.app."
  type        = string
  default     = "ecolors.app"
}

variable "create_parent_zone" {
  description = "Create the parent zone here. If false, set parent_zone_id to an existing one."
  type        = bool
  default     = true
}

variable "parent_zone_id" {
  description = "Existing parent zone id (when create_parent_zone = false)."
  type        = string
  default     = null
}
