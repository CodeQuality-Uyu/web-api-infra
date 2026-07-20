variable "client" {
  description = "Client slug, e.g. sayer."
  type        = string
}

variable "environment" {
  description = "dev | stage | prod."
  type        = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "tfc_organization" {
  description = "HCP Terraform organization (for reading consumer foundations' remote state)."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "enable_nat" {
  description = "NAT gateway — needed only if apps make outbound internet calls."
  type        = bool
  default     = true
}

variable "zone_name" {
  description = "Hosted zone / subdomain for this client, e.g. sayer.ecolors.app."
  type        = string
}

variable "create_zone" {
  type    = bool
  default = true
}

variable "zone_id" {
  type    = string
  default = null
}

variable "apps" {
  description = "App slugs for this client-env; one ECR repo ({client}-{app}-{env}) is created per app. Set by the factory."
  type        = list(string)
  default     = []
}

variable "databases" {
  description = "Distinct database names to create on the shared RDS (union of all apps' connections). Set by the factory."
  type        = list(string)
  default     = []
}

variable "db_public" {
  description = "Expose this client-env's RDS publicly so apps in OTHER accounts can reach shared databases here. Set true by the factory when another client-env references a db of this one."
  type        = bool
  default     = false
}

variable "db_consumer_workspaces" {
  description = "Foundation workspace names of the consumer client-envs (other accounts). Their NAT EIPs are read via remote state and allowlisted on the public RDS. Set by the factory."
  type        = list(string)
  default     = []
}

# --- Shared database (one RDS per client-env, one logical db per app) ---
variable "ssm_prefix" {
  description = "SSM path prefix for connection strings, e.g. /app."
  type        = string
  default     = "/app"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_deletion_protection" {
  type    = bool
  default = true
}

variable "db_skip_final_snapshot" {
  type    = bool
  default = false
}

variable "enable_github_oidc" {
  description = "Create the GitHub Actions OIDC provider (once per account) for migrations CI."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
