variable "tfc_organization" {
  description = "HCP Terraform organization. Scopes who can assume the tfc-deploy role in each account, and locates the management workspace's remote state."
  type        = string
  default     = "ColorLabs"
}

variable "management_workspace" {
  description = "HCP workspace of stacks/management, whose vended_account_ids / platform_account_ids outputs give the account ids to bootstrap."
  type        = string
  default     = "management"
}

variable "org_account_role" {
  description = "Role AWS Organizations auto-creates in each vended account, assumable from management. This stack assumes it to create tfc-deploy."
  type        = string
  default     = "OrganizationAccountAccessRole"
}
