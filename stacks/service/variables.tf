# --- Identity ---
variable "client" {
  description = "Client slug, e.g. sayer."
  type        = string
}

variable "app" {
  description = "App slug, e.g. webapi."
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

# --- Foundation (this client's) remote state ---
variable "tfc_organization" {
  description = "HCP Terraform organization."
  type        = string
}

variable "foundation_workspace" {
  description = "Name of this client's foundation workspace, e.g. sayer-dev-foundation."
  type        = string
}

# --- Application ---
variable "image_version" {
  description = "ECR image tag/version to run, e.g. \"1.4.0\". Composed with this app's ECR repo URL (from foundation) into the full image URI. Bump to promote a release; APP_VERSION_DATE is stamped automatically when this changes."
  type        = string
}

variable "container_port" {
  type    = string
  default = "8080"
}

variable "health_path" {
  type    = string
  default = "/health"
}

variable "cpu" {
  type    = string
  default = "1024"
}

variable "memory" {
  type    = string
  default = "2048"
}

variable "subdomain" {
  description = "Full app FQDN (a subdomain of the client zone), e.g. api.sayer.ecolors.app."
  type        = string
}

variable "runtime_env" {
  description = "Plaintext env vars for the app (.NET Key__Child style). Set by the factory from each app's `settings`. Overrides appsettings.json."
  type        = map(string)
  default     = {}
}

variable "secret_settings" {
  description = "Names of secret env vars (e.g. [\"Jwt__SigningKey\"]). Set by the factory. Each needs a value in `secret_values`; Terraform stores it in SSM SecureString and injects it as a runtime secret."
  type        = list(string)
  default     = []
}

variable "secret_values" {
  description = "Map of secret env var name -> value. Set this as a SENSITIVE variable on the service workspace (never in git). Must cover every name in secret_settings."
  type        = map(string)
  default     = {}
  sensitive   = true
}

# --- Database connections ---
variable "connections" {
  description = "Databases this app connects to. Each becomes ConnectionStrings__<key>. `source` set = a shared db in ANOTHER client-env's foundation (that foundation workspace name); absent = this client-env's own RDS. migrate=true marks a db this app owns (only local dbs are migrated)."
  type = list(object({
    key     = string
    db_name = string
    migrate = optional(bool, false)
    source  = optional(string) # provider foundation workspace name for a cross-env shared db
  }))
}

# --- Migrations ---
variable "github_repo" {
  description = "App repo \"org/repo\" for CodeBuild migrations + OIDC trust."
  type        = string
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "migration_buildspec" {
  type    = string
  default = "ci/migrate.buildspec.yml"
}

# --- Blobs (optional) ---
variable "create_blobs" {
  type    = bool
  default = false
}

variable "blobs_bucket_name" {
  type    = string
  default = null
}

variable "blobs_domain" {
  description = "e.g. assets.sayer.ecolors.app"
  type        = string
  default     = null
}

variable "blobs_allowed_origins" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
