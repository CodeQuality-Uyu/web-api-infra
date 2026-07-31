# --- Identity ---
variable "client" {
  description = "Client slug, e.g. sayer."
  type        = string
}

variable "environment" {
  description = "prod | nonprod | dev ..."
  type        = string
}

variable "frontend_name" {
  description = "Slug of this frontend within the client-env (e.g. \"admin\"). A client-env can host several SPAs, so this keeps resource names unique inside the account."
  type        = string
}

variable "consumes_apps" {
  description = "App slugs whose APIs this SPA calls. Documentation/tagging only — the API URL is build-time config in the frontend repo."
  type        = list(string)
  default     = []
}

variable "aws_account_id" {
  description = "AWS account this frontend must deploy into. Enforced via allowed_account_ids. Set by the factory."
  type        = string
  default     = null
}

# --- Foundation (this client's) remote state ---
variable "tfc_organization" {
  description = "HCP Terraform organization."
  type        = string
}

variable "foundation_workspace" {
  description = "This client-env's foundation workspace, e.g. sayer-prod-foundation. Provides zone_id / zone_name."
  type        = string
}

# --- Hosting ---
variable "bucket_name" {
  description = "Globally-unique S3 bucket for the built SPA."
  type        = string
}

variable "domain" {
  description = "Domain to serve the SPA on. Defaults to the client's ZONE APEX (foundation's zone_name) — i.e. what you type in the browser."
  type        = string
  default     = null
}

variable "subject_alternative_names" {
  description = "Extra domains that SERVE the same content (no redirect). For a canonical www use `www_redirect`."
  type        = list(string)
  default     = []
}

variable "www_redirect" {
  description = "Answer on www.<domain> and 301-redirect it to the apex, keeping one canonical URL. Mostly useful when the zone is a root domain (e.g. sayer.com), not a subdomain."
  type        = bool
  default     = false
}

variable "price_class" {
  type    = string
  default = "PriceClass_100"
}

# --- Release metadata ---
variable "release_version" {
  description = "FE version currently SERVED, e.g. \"1.0.0\". The CI uploads each release under a \"<version>/\" prefix; this drives CloudFront's origin_path (which version is live) and stamps the release date. Terraform never uploads content. Rollback = set this to a previously-uploaded version and apply."
  type        = string
  default     = "0.0.0"
}

variable "tags" {
  type    = map(string)
  default = {}
}
