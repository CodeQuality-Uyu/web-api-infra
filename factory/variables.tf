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
  description = "Override: HCP VCS OAuth token id (`ot-XXXX`). Normally leave null — it's looked up from the org's VCS connection via vcs_service_provider. When resolved, the factory connects EVERY child workspace to the repo (branch = version_tag); the working directory is already set per stack. All null (override + lookup) = workspaces created without VCS."
  type        = string
  default     = null
}

variable "vcs_service_provider" {
  description = "VCS connection type in HCP to resolve oauth_token_id from (e.g. \"github\", \"github_enterprise\", \"gitlab_hosted\"). Null skips the lookup. Ignored if oauth_token_id is set. If your org uses a GitHub App connection (not OAuth), set oauth_token_id explicitly instead."
  type        = string
  default     = "github"
}

variable "version_tag" {
  description = "Git tag every workspace tracks (pin releases; see VERSIONING.md)."
  type        = string
  default     = "v1.0.0"
}

variable "cors_settings_key" {
  description = "Config key the backends read their allowed origins from. Injected as an indexed .NET array: <key>__0, <key>__1, ... Matches appsettings { \"Cors\": { \"AllowedOrigins\": [...] } }."
  type        = string
  default     = "Cors__AllowedOrigins"
}

variable "tfc_role_name" {
  description = "IAM role each AWS account exposes for HCP dynamic provider credentials (OIDC). Must trust app.terraform.io. Overridable per client-env via aws_role_name."
  type        = string
  default     = "tfc-deploy"
}

variable "management_workspace" {
  description = "HCP workspace of stacks/management, whose `vended_account_ids` output supplies each client-env's account id (and `platform_account_ids` the infrastructure account). Null = require aws_account_id explicitly per client."
  type        = string
  default     = null
}

variable "infrastructure_workspace" {
  description = "HCP workspace of stacks/infrastructure, whose `parent_zone_id` output supplies the DNS delegation parent zone. Null = provide dns_parent_zone_id explicitly."
  type        = string
  default     = "infrastructure"
}

variable "infrastructure_account_key" {
  description = "Key of the infrastructure account in management's `platform_account_ids` map (owns the parent DNS zone)."
  type        = string
  default     = "infrastructure"
}

# --- Automatic DNS delegation ---
# Each foundation writes its zone's NS records into the parent zone (ecolors.app) cross-account.
# Both values below self-populate from remote state (management + infrastructure); set them only to
# override. Delegation stays off only if neither the remote state nor an explicit value resolves.
variable "dns_parent_account_id" {
  description = "Override: account that owns the parent zone. Defaults to the infrastructure account from management's platform_account_ids."
  type        = string
  default     = null
}

variable "dns_parent_zone_id" {
  description = "Override: hosted zone id of the parent zone. Defaults to the infrastructure stack's parent_zone_id output."
  type        = string
  default     = null
}

variable "dns_delegation_role_name" {
  description = "Name of the delegation role in the DNS-owning account (created by stacks/management)."
  type        = string
  default     = "dns-delegation"
}

# ============================================================================================
# The single source of truth: who exists, where they deploy, and who talks to whom.
#
# A client-env has `frontends` (SPAs) and `backends` (APIs). Anything pointing at ANOTHER
# client-env uses `source = { client, environment }` — that client-env may live in a different
# AWS account, which is fine.
# ============================================================================================
variable "clients" {
  description = "Client-envs with their frontends and backends."
  type = list(object({
    client      = string
    environment = string
    zone_name   = string
    # The AWS account this client-env deploys into. Usually DERIVED from the management stack's
    # vended accounts (see var.management_workspace) keyed by "{client}-{env}". Set it explicitly
    # only to override / for an account not vended by Terraform.
    aws_account_id = optional(string)
    aws_role_name  = optional(string) # defaults to var.tfc_role_name
    # App Runner size for every backend of this client-env. Default 1 vCPU / 2 GB; drop nonprod
    # to 0.5 vCPU / 1 GB to save (App Runner bills provisioned memory even at zero traffic).
    service_cpu    = optional(string, "1024")
    service_memory = optional(string, "2048")
    # Optional overnight pause of every backend (nonprod cost saving). Absent = never pause.
    service_pause = optional(object({
      pause_cron  = optional(string, "cron(0 2 * * ? *)") # 02:00 daily
      resume_cron = optional(string, "cron(0 7 * * ? *)") # 07:00 daily
      timezone    = optional(string, "America/Montevideo")
    }))

    # --- Frontends: static SPAs. Zero, one or many per client-env. ---------------------------
    # Domain is derived by convention as "<name>.<zone_name>". Set `serve_on_zone_root = true` for
    # the one that should answer on the zone itself, or `domain` for anything fully custom.
    frontends = optional(list(object({
      name        = string                    # slug; workspace = {client}-{name}-{env}-frontend
      version     = optional(string, "0.0.0") # what's published in the bucket
      github_repo = optional(string)          # repo that deploys it (for the github-deploy trust)
      bucket_name = optional(string)          # defaults to "{client}-{name}-{env}-web"

      # Serve this SPA on the zone itself (e.g. sayer.ecolors.app) instead of the derived
      # "<name>.<zone_name>" subdomain. At most one frontend per client-env may set it.
      serve_on_zone_root = optional(bool, false)
      domain             = optional(string) # fully custom domain; wins over serve_on_zone_root

      # Backends this SPA calls FROM THE BROWSER. Load-bearing: the factory inverts this to
      # generate each backend's CORS allowed origins. Include the identity provider — login is
      # browser-side, so the SPA's origin must be allowed there too.
      calls = optional(list(object({
        backend = string # `app` of a backend
        source = optional(object({ # omit when the backend is in THIS client-env
          client      = string
          environment = string
        }))
      })), [])

      subject_alternative_names = optional(list(string), []) # extra names that SERVE the same content
      # Answer on www.<domain> and 301 it to the apex. Worth it on a root domain (sayer.com);
      # pointless when the zone is already a subdomain (sayer.ecolors.app).
      www_redirect = optional(bool, false)
    })), [])

    # --- Backends: the APIs. ------------------------------------------------------------------
    backends = list(object({
      app     = string
      version = string
      # Databases this backend connects to. Each becomes a ConnectionStrings__<key> env var.
      # migrate = true marks a db this backend OWNS (its EF Core migrations run against it).
      connections = list(object({
        key     = string
        db_name = string
        migrate = optional(bool, false)
        source = optional(object({ # the db lives in ANOTHER client-env (shared, cross-account)
          client      = string
          environment = string
        }))
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
      # Origins to allow in CORS on top of the ones derived from the frontends (e.g. a local
      # dev server "http://localhost:5173" in nonprod).
      extra_cors_origins = optional(list(string), [])

      # Blob storage (multimedia: product images, downloadable Excels, ...). Opt in with `blobs = {}`
      # — creates a private S3 bucket + a CloudFront CDN, grants this backend runtime R/W, and
      # injects the Blob__* env vars. Uploads use presigned PUT (browser -> S3, allowed via CORS
      # from the same origins that call this backend); reads are served from the CDN. Omit = no blobs.
      blobs = optional(object({
        domain      = optional(string) # CDN domain; defaults to "assets.<zone_name>" of this client-env
        bucket_name = optional(string) # defaults to "{client}-{app}-{env}-blobs"
      }))
    }))
  }))
  default = []

  # Only one site can answer on the bare zone.
  validation {
    condition = alltrue([
      for c in var.clients :
      length([for f in c.frontends : f if try(f.serve_on_zone_root, false)]) <= 1
    ])
    error_message = "At most one frontend per client-env may set serve_on_zone_root = true."
  }

  # Frontend names key the workspace/bucket, so they must be unique within a client-env.
  validation {
    condition = alltrue([
      for c in var.clients :
      length(distinct([for f in c.frontends : f.name])) == length(c.frontends)
    ])
    error_message = "Frontend `name` must be unique within a client-env."
  }

  # Backend slugs must be unique within a client-env (they key the workspace and the ECR repo).
  validation {
    condition = alltrue([
      for c in var.clients :
      length(distinct([for b in c.backends : b.app])) == length(c.backends)
    ])
    error_message = "Backend `app` must be unique within a client-env."
  }

  # A blobs CDN domain (explicit, or the computed "assets.<zone>") must sit under the client-env's
  # zone: the module validates its ACM cert and writes the alias in that zone, so a domain outside
  # it could never resolve or validate. Only bites when someone sets `domain` explicitly.
  validation {
    condition = alltrue(flatten([
      for c in var.clients : [
        for b in c.backends :
        endswith(coalesce(try(b.blobs.domain, null), "assets.${c.zone_name}"), c.zone_name)
        if try(b.blobs, null) != null
      ]
    ]))
    error_message = "Each backend `blobs.domain` must be within the client-env's `zone_name` (e.g. assets.sayer.ecolors.app under sayer.ecolors.app)."
  }

  # Two backends in the same client-env can't share a blobs CDN domain (one CloudFront alias each).
  # Since the default is the same "assets.<zone>", at most ONE backend per client-env can use the
  # default; the rest must set an explicit `domain`.
  validation {
    condition = alltrue([
      for c in var.clients :
      length([for b in c.backends : coalesce(try(b.blobs.domain, null), "assets.${c.zone_name}") if try(b.blobs, null) != null]) ==
      length(distinct([for b in c.backends : coalesce(try(b.blobs.domain, null), "assets.${c.zone_name}") if try(b.blobs, null) != null]))
    ])
    error_message = "Each backend's blobs CDN domain must be unique within a client-env; set an explicit `blobs.domain` when more than one backend needs blobs."
  }

  # Every `source` (in frontend calls and in db connections) must name a client-env that exists.
  validation {
    condition = alltrue(flatten([
      for c in var.clients : [
        for f in c.frontends : [
          for call in f.calls :
          anytrue([
            for cc in var.clients :
            cc.client == call.source.client && cc.environment == call.source.environment
          ])
          if try(call.source, null) != null
        ]
      ]
    ]))
    error_message = "A frontend call's `source` must be a client-env defined in this file ({ client, environment })."
  }

  validation {
    condition = alltrue(flatten([
      for c in var.clients : [
        for b in c.backends : [
          for conn in b.connections :
          anytrue([
            for cc in var.clients :
            cc.client == conn.source.client && cc.environment == conn.source.environment
          ])
          if try(conn.source, null) != null
        ]
      ]
    ]))
    error_message = "A connection's `source` must be a client-env defined in this file ({ client, environment })."
  }

  # A called backend must actually exist in the target client-env — otherwise the CORS origin
  # would be silently dropped and the browser would fail at runtime.
  validation {
    condition = alltrue(flatten([
      for c in var.clients : [
        for f in c.frontends : [
          for call in f.calls :
          anytrue([
            for cc in var.clients :
            contains([for b in cc.backends : b.app], call.backend)
            if cc.client == try(call.source.client, c.client) && cc.environment == try(call.source.environment, c.environment)
          ])
        ]
      ]
    ]))
    error_message = "Each frontend call must name a backend that exists in the target client-env (its own, or the one given by `source`)."
  }

  # A shared (cross-env) connection is never migrated by the consumer — its owner migrates it.
  validation {
    condition = alltrue(flatten([
      for c in var.clients : [
        for b in c.backends : [
          for conn in b.connections :
          try(conn.migrate, false) == false
          if try(conn.source, null) != null
        ]
      ]
    ]))
    error_message = "A connection with `source` must not set migrate = true; a shared db is migrated by its owning backend in the provider client-env."
  }

  # A shared connection's db_name must actually be created by the provider — i.e. some backend
  # there owns it via a LOCAL connection (one without `source`).
  validation {
    condition = alltrue(flatten([
      for c in var.clients : [
        for b in c.backends : [
          for conn in b.connections :
          anytrue([
            for cc in var.clients :
            contains(
              flatten([for bb in cc.backends : [for cn in bb.connections : cn.db_name if try(cn.source, null) == null]]),
              conn.db_name
            )
            if cc.client == try(conn.source.client, "") && cc.environment == try(conn.source.environment, "")
          ])
          if try(conn.source, null) != null
        ]
      ]
    ]))
    error_message = "A `source` connection's db_name must be a local database of that provider client-env (some backend there must own it via a connection without `source`)."
  }
}
