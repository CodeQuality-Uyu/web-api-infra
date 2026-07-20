variable "organization" {
  description = "HCP Terraform organization."
  type        = string
}

variable "vcs_identifier" {
  description = "VCS repo, e.g. CodeQuality-Uyu/web-api-infra."
  type        = string
  default     = "CodeQuality-Uyu/web-api-infra"
}

variable "oauth_token_id" {
  description = "HCP VCS connection OAuth token id (from the org's VCS provider settings)."
  type        = string
}

variable "version_tag" {
  description = "Git tag every workspace tracks (pin releases; see VERSIONING.md)."
  type        = string
  default     = "v1.0.0"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# The single source of truth for who exists. Add a client or an app here.
variable "clients" {
  description = "Clients and their apps."
  type = list(object({
    client      = string
    environment = string
    zone_name   = string
    apps = list(object({
      app     = string
      version = string
      # Databases this app connects to. Each becomes a ConnectionStrings__<key> env var pointing
      # at that db's connection string on the shared RDS. Exactly one should have migrate = true:
      # the app's OWN database, the one its EF Core migrations run against.
      connections = list(object({
        key     = string
        db_name = string
        migrate = optional(bool, false)
        # For a db that lives in ANOTHER client-env (shared, cross-account), set source to that
        # client-env's foundation workspace name, e.g. "ecolors-prod-foundation". Absent = local.
        source = optional(string)
      }))
      subdomain   = string
      github_repo = string
      # .NET-style env vars (Key__Child) injected into App Runner. Plaintext config only —
      # values live in git. Overrides appsettings.json.
      settings = optional(map(string), {})
      # NAMES of secret env vars (e.g. ["Jwt__SigningKey"]). Values are NOT in git — set them
      # as a sensitive `secret_values` map on the service workspace; Terraform stores each in
      # SSM SecureString and injects it as a runtime secret.
      secret_settings = optional(list(string), [])
    }))
  }))
  default = []

  # A connection's `source` must name an existing foundation ("{client}-{environment}-foundation").
  validation {
    condition = alltrue(flatten([
      for c in var.clients : [
        for a in c.apps : [
          for conn in a.connections :
          contains([for cc in var.clients : "${cc.client}-${cc.environment}-foundation"], conn.source)
          if try(conn.source, null) != null
        ]
      ]
    ]))
    error_message = "Each connection `source` must be an existing foundation workspace named \"{client}-{environment}-foundation\" (a client-env defined in this file)."
  }

  # A shared (cross-env) connection is never migrated by the consumer — its owner migrates it.
  validation {
    condition = alltrue(flatten([
      for c in var.clients : [
        for a in c.apps : [
          for conn in a.connections :
          try(conn.migrate, false) == false
          if try(conn.source, null) != null
        ]
      ]
    ]))
    error_message = "A connection with `source` must not set migrate = true; a shared db is migrated by its owning app in the provider client-env."
  }

  # A shared connection's db_name must actually be created by the provider — i.e. some app in
  # that provider client-env owns it via a LOCAL connection (one without `source`).
  validation {
    condition = alltrue(flatten([
      for c in var.clients : [
        for a in c.apps : [
          for conn in a.connections :
          anytrue([
            for cc in var.clients :
            contains(
              flatten([for aa in cc.apps : [for cn in aa.connections : cn.db_name if try(cn.source, null) == null]]),
              conn.db_name
            )
            if "${cc.client}-${cc.environment}-foundation" == conn.source
          ])
          if try(conn.source, null) != null
        ]
      ]
    ]))
    error_message = "A `source` connection's db_name must be a local database of that provider client-env (some app there must own it via a connection without `source`)."
  }
}
