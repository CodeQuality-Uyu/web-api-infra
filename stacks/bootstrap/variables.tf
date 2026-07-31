
variable "aws_account_id" {
  description = "The account being bootstrapped. Guardrail: apply fails if the session belongs to another account."
  type        = string
}

variable "tfc_organization" {
  description = "HCP Terraform organization, e.g. \"ColorLabs\"."
  type        = string
}

variable "role_name" {
  description = "Role name HCP Terraform assumes. Keep in sync with the factory's tfc_role_name (member accounts) or use tfc-org-admin for the management account."
  type        = string
  default     = "tfc-deploy"
}

variable "role_profile" {
  description = "\"workload\" for member accounts (the client-envs), \"org-admin\" for the management/root account."
  type        = string
  default     = "workload"
}

variable "create_tfc_oidc_provider" {
  description = "Create the app.terraform.io OIDC provider. Set false if it already exists in this account."
  type        = bool
  default     = true
}

variable "tfc_allowed_subs" {
  description = "Optional: tighten which workspaces/projects can assume the role (app.terraform.io:sub). Default: all in the org."
  type        = list(string)
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
