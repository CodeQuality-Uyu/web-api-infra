variable "client" {
  description = "Client slug, e.g. sayer."
  type        = string
}

variable "environment" {
  description = "dev | stage | prod."
  type        = string
}

variable "tfc_organization" {
  description = "HCP Terraform organization (for reading consumer foundations' remote state)."
  type        = string
  default     = null
}

variable "aws_account_id" {
  description = "AWS account this client-env must deploy into. Enforced via allowed_account_ids — a credential for any other account fails the plan instead of creating resources in the wrong place. Set by the factory."
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

variable "enable_bastion" {
  description = "SSM bastion for occasional manual DB admin. Off by default (on-demand); enable for a session, then disable. Apps/migrations reach RDS without it."
  type        = bool
  default     = false
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

# --- Automatic DNS delegation (optional) ---
# When both are set, the foundation writes its zone's NS records into the PARENT zone
# (ecolors.app) cross-account, so the subdomain delegates itself. Unset = manual delegation.
variable "dns_parent_zone_id" {
  description = "Hosted zone id of the parent zone (ecolors.app), in the DNS-owning account."
  type        = string
  default     = null
}

variable "dns_delegation_role_arn" {
  description = "ARN of the dns-delegation role (in the DNS-owning account) this foundation assumes to write its NS records."
  type        = string
  default     = null
}

variable "enable_github_oidc" {
  description = "Create the GitHub Actions OIDC provider (once per account) for migrations CI + the deploy role."
  type        = bool
  default     = true
}

variable "github_repos" {
  description = "App repos that deploy into this account (org/repo). Drives the github-deploy role's trust. Set by the factory."
  type        = list(string)
  default     = []
}

variable "frontend_buckets" {
  description = "Frontend S3 bucket names in this client-env; the github-deploy role may sync into them. Set by the factory."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
