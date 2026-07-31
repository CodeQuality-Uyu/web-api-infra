variable "role_name" {
  description = "Name of the role HCP Terraform assumes to deploy. Must match the factory's tfc_role_name."
  type        = string
  default     = "tfc-deploy"
}

variable "profile" {
  description = "Permission profile. \"workload\" (member accounts): infra services, DENY org/billing/users. \"org-admin\" (management account): organizations/SSO/account/billing, still DENY static creds + self-tampering."
  type        = string
  default     = "workload"
  validation {
    condition     = contains(["workload", "org-admin"], var.profile)
    error_message = "profile must be \"workload\" or \"org-admin\"."
  }
}

variable "tfc_organization" {
  description = "HCP Terraform organization, e.g. \"ColorLabs\". Used to scope who can assume the role."
  type        = string
}

variable "tfc_allowed_subs" {
  description = "Allowed values for the app.terraform.io:sub claim (StringLike). Default: every workspace/project in the org. Tighten to specific projects/workspaces for least privilege."
  type        = list(string)
  default     = null
}

variable "create_tfc_oidc_provider" {
  description = "Create the app.terraform.io OIDC provider in this account. Set false if it already exists (only one per account is allowed)."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
