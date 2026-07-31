variable "hosted_zone_id" {
  description = "The PARENT hosted zone (e.g. ecolors.app) into which client foundations write their NS delegation records."
  type        = string
}

variable "org_id" {
  description = "AWS Organizations id (o-xxxx). The role only trusts principals inside this org."
  type        = string
}

variable "role_name" {
  description = "Name of the delegation role. Client foundations assume this by ARN."
  type        = string
  default     = "dns-delegation"
}

variable "consumer_role_name" {
  description = "Which role in member accounts may assume this (the workload deploy role)."
  type        = string
  default     = "tfc-deploy"
}

variable "tags" {
  type    = map(string)
  default = {}
}
