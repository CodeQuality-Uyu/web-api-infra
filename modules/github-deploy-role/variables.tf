variable "role_name" {
  description = "Role name GitHub Actions assumes to deploy into this account. Parallel to tfc-deploy."
  type        = string
  default     = "github-deploy"
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider (token.actions.githubusercontent.com) in this account."
  type        = string
}

variable "github_repos" {
  description = "Repos allowed to assume the role, as \"org/repo\". Trust is scoped to their main branch and tags."
  type        = list(string)
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs this role may push to (created by the foundation)."
  type        = list(string)
  default     = []
}

variable "frontend_bucket_arns" {
  description = "S3 bucket ARNs (frontend) this role may sync objects into."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
