variable "name" {
  description = "Prefix, usually \"{client}-{app}-{env}\"."
  type        = string
}

variable "github_repo" {
  description = "App repo as \"org/repo\" — CodeBuild source + OIDC trust scope."
  type        = string
}

variable "github_branch" {
  description = "Default branch/ref for the CodeBuild source."
  type        = string
  default     = "main"
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (created once per account in the foundation)."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets for CodeBuild (must reach RDS)."
  type        = list(string)
}

variable "security_group_ids" {
  description = "SGs for CodeBuild ENIs (typically the shared db_clients SG that RDS allows)."
  type        = list(string)
}

variable "buildspec" {
  description = "Path (in the app repo) to the migration buildspec."
  type        = string
  default     = "ci/migrate.buildspec.yml"
}

variable "env" {
  description = "Plaintext env vars for the migration build (e.g. DB_HOST)."
  type        = map(string)
  default     = {}
}

variable "secret_source_arns" {
  description = "SSM/Secrets ARNs the build may read (the DB connection string)."
  type        = list(string)
  default     = []
}

variable "kms_key_arns" {
  description = "KMS keys the build may Decrypt."
  type        = list(string)
  default     = []
}

variable "codebuild_image" {
  type    = string
  default = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
}

variable "tags" {
  type    = map(string)
  default = {}
}
