# ============================================================================
# Client factory: one definition (clients.auto.tfvars) -> all workspaces + vars.
# Onboarding a client = a foundation workspace; onboarding an app = a service
# workspace with a run-trigger from its client's foundation.
# ============================================================================

# The management stack vends the accounts; read their ids so aws_account_id doesn't have to be
# hardcoded per client. Keyed "{client}-{env}" (same as our foundations).
data "terraform_remote_state" "management" {
  count = var.management_workspace == null ? 0 : 1

  backend = "remote"
  config = {
    organization = var.organization
    workspaces = {
      name = var.management_workspace
    }
  }
}

# The infrastructure stack owns the parent DNS zone; read its parent_zone_id so the delegation
# doesn't have to be pasted in by hand.
data "terraform_remote_state" "infrastructure" {
  count = var.infrastructure_workspace == null ? 0 : 1

  backend = "remote"
  config = {
    organization = var.organization
    workspaces = {
      name = var.infrastructure_workspace
    }
  }
}

# Resolve the VCS connection's OAuth token id from HCP itself, so the opaque "ot-XXXX" doesn't have
# to be pasted in. Skipped when oauth_token_id is set explicitly or vcs_service_provider is null.
data "tfe_oauth_client" "vcs" {
  count = var.oauth_token_id != null || var.vcs_service_provider == null ? 0 : 1

  organization     = var.organization
  service_provider = var.vcs_service_provider
}

locals {
  # OAuth token id for wiring child workspaces to VCS: explicit override, else looked up from the
  # org's VCS connection, else null (workspaces created without VCS).
  oauth_token_id = var.oauth_token_id != null ? var.oauth_token_id : try(data.tfe_oauth_client.vcs[0].oauth_token_id, null)

  # Client-envs, keyed "{client}-{env}". This key is the id used everywhere below; the matching
  # workspace is always "{key}-foundation".
  foundations = { for c in var.clients : "${c.client}-${c.environment}" => c }

  # Account id per client-env: explicit override, else the vended id from management.
  vended_accounts = var.management_workspace == null ? {} : data.terraform_remote_state.management[0].outputs.vended_account_ids
  account_id      = { for k, c in local.foundations : k => coalesce(try(c.aws_account_id, null), try(local.vended_accounts[k], null)) }

  # DNS delegation parent — both self-populate from remote state (management vends the infrastructure
  # account; the infrastructure stack outputs its zone id). Explicit vars still win as an override.
  dns_parent_account_id = coalesce(
    var.dns_parent_account_id,
    try(data.terraform_remote_state.management[0].outputs.platform_account_ids[var.infrastructure_account_key], null),
  )
  dns_parent_zone_id = coalesce(
    var.dns_parent_zone_id,
    try(data.terraform_remote_state.infrastructure[0].outputs.parent_zone_id, null),
  )

  # Every backend (API) across all client-envs, keyed "{client}-{app}-{env}".
  backends = merge([
    for c in var.clients : {
      for b in c.backends :
      "${c.client}-${b.app}-${c.environment}" => merge(b, {
        client         = c.client
        environment    = c.environment
        foundation_key = "${c.client}-${c.environment}"
        foundation     = "${c.client}-${c.environment}-foundation"
      })
    }
  ]...)

  # Role each workspace assumes via HCP dynamic provider credentials (OIDC). The ARN pins the
  # AWS account (from the vended/derived account id) + the role name.
  account_role_arn = {
    for k, c in local.foundations :
    k => "arn:aws:iam::${local.account_id[k]}:role/${coalesce(c.aws_role_name, var.tfc_role_name)}"
  }

  # For the github-deploy role in each foundation: the repos that deploy here (backends + FEs)
  # and the FE bucket names (so the role can push images and sync frontends).
  github_repos = {
    for k, c in local.foundations : k => distinct(concat(
      [for b in c.backends : b.github_repo],
      [for f in c.frontends : f.github_repo if try(f.github_repo, null) != null],
    ))
  }
  frontend_buckets = {
    for k, c in local.foundations : k => [
      for f in c.frontends : coalesce(f.bucket_name, "${c.client}-${f.name}-${c.environment}-web")
    ]
  }

  # --- Cross-env shared-DB topology ---------------------------------------------------------
  # Every connection with `source` = a consumer client-env depending on a provider client-env.
  external_links = flatten([
    for k, b in local.backends : [
      for conn in b.connections : {
        provider = "${conn.source.client}-${conn.source.environment}"
        consumer = b.foundation_key
      } if try(conn.source, null) != null
    ]
  ])

  # provider client-env key -> distinct consumer FOUNDATION WORKSPACE names (what the provider
  # foundation reads to allowlist their NAT egress IPs).
  db_providers = {
    for p in distinct([for l in local.external_links : l.provider]) :
    p => distinct([for l in local.external_links : "${l.consumer}-foundation" if l.provider == p])
  }

  # Distinct (provider, consumer) client-env pairs, for run-trigger ordering.
  provider_consumer_pairs = {
    for l in local.external_links : "${l.provider}<=${l.consumer}" => l...
  }

  # --- Frontends ------------------------------------------------------------------------------
  # Keyed "{client}-{name}-{env}". Domain is derived by convention as "<name>.<zone>";
  # `serve_on_zone_root` puts it on the zone itself and `domain` overrides everything.
  frontends = merge([
    for k, c in local.foundations : {
      for f in c.frontends :
      "${c.client}-${f.name}-${c.environment}" => merge(f, {
        foundation_key = k
        client         = c.client
        environment    = c.environment
        # Resolved HERE (not only in the stack) because CORS derivation needs the browser origin
        # of every SPA.
        resolved_domain = coalesce(f.domain, f.serve_on_zone_root ? c.zone_name : "${f.name}.${c.zone_name}")
        # Every origin a browser can load this SPA from. `www_redirect` is excluded on purpose:
        # it 301s to the zone root, so the SPA never actually runs on the www origin.
        origins = [
          for d in concat(
            [coalesce(f.domain, f.serve_on_zone_root ? c.zone_name : "${f.name}.${c.zone_name}")],
            f.subject_alternative_names,
          ) : "https://${d}"
        ]
      })
    }
  ]...)

  # --- CORS derivation ------------------------------------------------------------------------
  # Browser-side auth means each SPA calls its own API *and* the identity provider, sometimes in
  # another account. Every frontend declares what it calls; here we INVERT that relationship so
  # each backend learns which origins must be allowed. Keeping this derived (instead of
  # hand-written) is what prevents "we added a frontend and login broke in production".
  call_edges = flatten([
    for fk, f in local.frontends : [
      for call in f.calls : {
        # Fully-qualified backend key. Without `source` the backend belongs to the frontend's own
        # client-env; with it, to the client-env named in the source object.
        backend_key = format(
          "%s-%s-%s",
          try(call.source.client, f.client),
          call.backend,
          try(call.source.environment, f.environment),
        )
        origins = f.origins
      }
    ]
  ])

  # Backend key -> allowed origins (derived from frontends + anything declared on the backend).
  # Sorted so the generated indices stay stable and don't produce spurious diffs.
  backend_cors_origins = {
    for k, b in local.backends :
    k => sort(distinct(concat(
      flatten([for e in local.call_edges : e.origins if e.backend_key == k]),
      try(b.extra_cors_origins, []),
    )))
  }

  # Rendered as the indexed .NET array the backends bind to: Cors__AllowedOrigins__0, __1, ...
  cors_settings = {
    for k, origins in local.backend_cors_origins :
    k => { for i, o in origins : "${var.cors_settings_key}__${i}" => o }
  }

  # Backends that opt into blob storage. Bucket name defaults to {client}-{app}-{env}-blobs; the
  # upload-CORS origins reuse the same browser origins derived for this backend's API CORS (the
  # SPA that calls the API is the one doing presigned PUTs).
  blobs_backends = {
    for k, b in local.backends : k => {
      # Default CDN domain: assets.<client-env zone>. Override only when a client-env needs blobs on
      # more than one backend (they'd otherwise collide on the same assets.<zone>).
      domain      = coalesce(try(b.blobs.domain, null), "assets.${local.foundations[b.foundation_key].zone_name}")
      bucket_name = coalesce(try(b.blobs.bucket_name, null), "${b.client}-${b.app}-${b.environment}-blobs")
      origins     = local.backend_cors_origins[k]
    } if try(b.blobs, null) != null
  }
}

# --- Foundation workspaces (one per client-env) ---
resource "tfe_workspace" "foundation" {
  for_each = local.foundations

  name              = "${each.key}-foundation"
  organization      = var.organization
  tag_names         = ["foundation"]
  working_directory = "stacks/foundation"
  auto_apply        = false

  # Set oauth_token_id to wire VCS on every child automatically (repo + branch = version_tag). The
  # working directory is already set above, so each workspace lands on the right folder. Left null,
  # the workspaces are created WITHOUT a VCS connection (don't then attach it by hand — the factory
  # owns this and would revert it; provide the token instead).
  dynamic "vcs_repo" {
    for_each = local.oauth_token_id == null ? [] : [1]
    content {
      identifier     = var.vcs_identifier
      branch         = var.version_tag
      oauth_token_id = local.oauth_token_id
    }
  }

}

# Foundations expose outputs consumed cross-workspace (services read DB creds; a provider
# foundation reads consumer NAT EIPs). Share state org-wide so those reads work.
resource "tfe_workspace_settings" "foundation" {
  for_each = tfe_workspace.foundation

  workspace_id        = each.value.id
  global_remote_state = true
}

resource "tfe_variable" "foundation" {
  for_each = merge([
    for k, c in local.foundations : {
      "${k}-client"      = { ws = k, key = "client", value = c.client }
      "${k}-environment" = { ws = k, key = "environment", value = c.environment }
      "${k}-zone"        = { ws = k, key = "zone_name", value = c.zone_name }
      "${k}-org"         = { ws = k, key = "tfc_organization", value = var.organization }
      "${k}-account"     = { ws = k, key = "aws_account_id", value = local.account_id[k] }
      # Provider flag: is any db of this client-env referenced externally?
      "${k}-db_public" = { ws = k, key = "db_public", value = contains(keys(local.db_providers), k) ? "true" : "false" }
    }
  ]...)

  workspace_id = tfe_workspace.foundation[each.value.ws].id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
}

# App slugs → one ECR repo each. HCL-typed (a list).
resource "tfe_variable" "foundation_apps" {
  for_each = local.foundations

  workspace_id = tfe_workspace.foundation[each.key].id
  key          = "apps"
  value        = jsonencode([for b in each.value.backends : b.app])
  category     = "terraform"
  hcl          = true
  description  = "App slugs; foundation creates one ECR repo ({client}-{app}-{env}) per app."
}

# Repos that deploy into this account (github-deploy trust) + FE bucket names.
resource "tfe_variable" "foundation_github" {
  for_each = merge([
    for k in keys(local.foundations) : {
      "${k}-repos"   = { ws = k, key = "github_repos", value = jsonencode(local.github_repos[k]) }
      "${k}-buckets" = { ws = k, key = "frontend_buckets", value = jsonencode(local.frontend_buckets[k]) }
    }
  ]...)

  workspace_id = tfe_workspace.foundation[each.value.ws].id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
  hcl          = true
  description  = "github-deploy role inputs: repos allowed + FE buckets."
}

# The union of every db_name referenced by this client-env's apps → one database each on the
# shared RDS (created once even if multiple apps connect to it).
resource "tfe_variable" "foundation_databases" {
  for_each = local.foundations

  workspace_id = tfe_workspace.foundation[each.key].id
  key          = "databases"
  # Only LOCAL connections (no `source`) — a `source` db lives in another client-env's RDS, so
  # this foundation must not create a duplicate for it.
  value       = jsonencode(distinct(flatten([for b in each.value.backends : [for c in b.connections : c.db_name if try(c.source, null) == null]])))
  category    = "terraform"
  hcl         = true
  description = "Distinct LOCAL database names (connections without `source`). Foundation creates one per name."
}

# Consumer foundations (other client-envs) whose NAT EIPs this provider must allowlist.
resource "tfe_variable" "foundation_consumers" {
  for_each = local.foundations

  workspace_id = tfe_workspace.foundation[each.key].id
  key          = "db_consumer_workspaces"
  value        = jsonencode(try(local.db_providers[each.key], []))
  category     = "terraform"
  hcl          = true
  description  = "Consumer foundation workspace names; their NAT EIPs are allowlisted on the public RDS."
}

# Automatic DNS delegation: every foundation writes its NS records into the parent zone
# cross-account. Self-configures from remote state; skipped only if the parent can't be resolved.
resource "tfe_variable" "foundation_dns" {
  for_each = local.dns_parent_account_id == null || local.dns_parent_zone_id == null ? {} : merge([
    for k in keys(local.foundations) : {
      "${k}-zone" = { ws = k, key = "dns_parent_zone_id", value = local.dns_parent_zone_id }
      "${k}-role" = { ws = k, key = "dns_delegation_role_arn", value = "arn:aws:iam::${local.dns_parent_account_id}:role/${var.dns_delegation_role_name}" }
    }
  ]...)

  workspace_id = tfe_workspace.foundation[each.value.ws].id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
  description  = "Cross-account NS delegation into the parent zone."
}

# --- Service workspaces (one per app) ---
resource "tfe_workspace" "service" {
  for_each = local.backends

  name              = "${each.key}-service"
  organization      = var.organization
  tag_names         = ["service"]
  working_directory = "stacks/service"
  auto_apply        = false

  # Set oauth_token_id to wire VCS on every child automatically (repo + branch = version_tag). The
  # working directory is already set above, so each workspace lands on the right folder. Left null,
  # the workspaces are created WITHOUT a VCS connection (don't then attach it by hand — the factory
  # owns this and would revert it; provide the token instead).
  dynamic "vcs_repo" {
    for_each = local.oauth_token_id == null ? [] : [1]
    content {
      identifier     = var.vcs_identifier
      branch         = var.version_tag
      oauth_token_id = local.oauth_token_id
    }
  }

}

resource "tfe_variable" "service" {
  for_each = merge([
    for k, a in local.backends : {
      "${k}-client"       = { ws = k, key = "client", value = a.client }
      "${k}-app"          = { ws = k, key = "app", value = a.app }
      "${k}-environment"  = { ws = k, key = "environment", value = a.environment }
      "${k}-org"          = { ws = k, key = "tfc_organization", value = var.organization }
      "${k}-foundation"   = { ws = k, key = "foundation_workspace", value = a.foundation }
      "${k}-account"      = { ws = k, key = "aws_account_id", value = local.account_id[a.foundation_key] }
      "${k}-version"      = { ws = k, key = "image_version", value = a.version }
      "${k}-subdomain"    = { ws = k, key = "subdomain", value = a.subdomain }
      "${k}-github_repo"  = { ws = k, key = "github_repo", value = a.github_repo }
      "${k}-cpu"          = { ws = k, key = "cpu", value = local.foundations[a.foundation_key].service_cpu }
      "${k}-memory"       = { ws = k, key = "memory", value = local.foundations[a.foundation_key].service_memory }
    }
  ]...)

  workspace_id = tfe_workspace.service[each.value.ws].id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
}

# Overnight pause schedule (per client-env, applied to every backend when set).
resource "tfe_variable" "service_pause" {
  for_each = merge([
    for k, a in local.backends : {
      "${k}-pause"  = { ws = k, key = "pause_cron", value = local.foundations[a.foundation_key].service_pause.pause_cron }
      "${k}-resume" = { ws = k, key = "resume_cron", value = local.foundations[a.foundation_key].service_pause.resume_cron }
      "${k}-tz"     = { ws = k, key = "schedule_timezone", value = local.foundations[a.foundation_key].service_pause.timezone }
    } if try(local.foundations[a.foundation_key].service_pause, null) != null
  ]...)

  workspace_id = tfe_workspace.service[each.value.ws].id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
}

# HCL-typed service vars (a map / a list). Plaintext app config + the NAMES of secret env
# vars. Secret VALUES are never set here — they go in the workspace's sensitive `secret_values`.
resource "tfe_variable" "service_settings" {
  for_each = local.backends

  workspace_id = tfe_workspace.service[each.key].id
  key          = "runtime_env"
  # Declared settings + the CORS origins derived from whichever frontends call this API.
  # Derived values win: the topology is the source of truth for allowed origins.
  value       = jsonencode(merge(each.value.settings, local.cors_settings[each.key]))
  category    = "terraform"
  hcl         = true
  description = ".NET env vars (Key__Child) for App Runner. Includes CORS origins derived from the frontends that consume this API."
}

# Blob storage (string inputs) for backends that opt in. create_blobs + allowed_origins (HCL)
# are set in the next resource. Backends without `blobs` leave create_blobs at its false default.
resource "tfe_variable" "service_blobs" {
  for_each = merge([
    for k, blob in local.blobs_backends : {
      "${k}-bucket" = { ws = k, key = "blobs_bucket_name", value = blob.bucket_name }
      "${k}-domain" = { ws = k, key = "blobs_domain", value = blob.domain }
    }
  ]...)

  workspace_id = tfe_workspace.service[each.value.ws].id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
}

resource "tfe_variable" "service_blobs_hcl" {
  for_each = merge([
    for k, blob in local.blobs_backends : {
      "${k}-enable"  = { ws = k, key = "create_blobs", value = "true" }
      "${k}-origins" = { ws = k, key = "blobs_allowed_origins", value = jsonencode(blob.origins) }
    }
  ]...)

  workspace_id = tfe_workspace.service[each.value.ws].id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
  hcl          = true
  description  = "Blob storage toggle + upload-CORS origins for this backend."
}

resource "tfe_variable" "service_secret_settings" {
  for_each = local.backends

  workspace_id = tfe_workspace.service[each.key].id
  key          = "secret_settings"
  value        = jsonencode(each.value.secret_settings)
  category     = "terraform"
  hcl          = true
  description  = "Names of secret env vars; provide their values via the sensitive secret_values map on this workspace."
}

# The app's database connections: [{ key, db_name, migrate }]. One ConnectionStrings__<key>
# per entry; the migrate=true one is the app's own db (what EF Core migrates).
resource "tfe_variable" "service_connections" {
  for_each = local.backends

  workspace_id = tfe_workspace.service[each.key].id
  key          = "connections"
  # `source` is a { client, environment } object in clients.auto.tfvars (readable), but the
  # service stack consumes it as the provider's foundation WORKSPACE name. Normalize here so the
  # stack contract stays a plain string.
  value = jsonencode([
    for c in each.value.connections : {
      key     = c.key
      db_name = c.db_name
      migrate = try(c.migrate, false)
      source  = try(c.source, null) == null ? null : "${c.source.client}-${c.source.environment}-foundation"
    }
  ])
  category    = "terraform"
  hcl         = true
  description = "DB connections for this backend. migrate=true marks a db it owns."
}

# --- Frontend workspaces (one per declared frontend; a client-env can have several) ---
resource "tfe_workspace" "frontend" {
  for_each = local.frontends

  name              = "${each.key}-frontend" # {client}-{name}-{env}-frontend
  organization      = var.organization
  tag_names         = ["frontend"]
  working_directory = "stacks/frontend"
  auto_apply        = false

  # Set oauth_token_id to wire VCS on every child automatically (repo + branch = version_tag). The
  # working directory is already set above, so each workspace lands on the right folder. Left null,
  # the workspaces are created WITHOUT a VCS connection (don't then attach it by hand — the factory
  # owns this and would revert it; provide the token instead).
  dynamic "vcs_repo" {
    for_each = local.oauth_token_id == null ? [] : [1]
    content {
      identifier     = var.vcs_identifier
      branch         = var.version_tag
      oauth_token_id = local.oauth_token_id
    }
  }

}

resource "tfe_variable" "frontend" {
  for_each = merge([
    for k, f in local.frontends : {
      "${k}-client"      = { ws = k, key = "client", value = f.client }
      "${k}-environment" = { ws = k, key = "environment", value = f.environment }
      "${k}-name"        = { ws = k, key = "frontend_name", value = f.name }
      "${k}-org"         = { ws = k, key = "tfc_organization", value = var.organization }
      "${k}-foundation"  = { ws = k, key = "foundation_workspace", value = "${f.foundation_key}-foundation" }
      "${k}-account"     = { ws = k, key = "aws_account_id", value = local.account_id[f.foundation_key] }
      "${k}-version"     = { ws = k, key = "release_version", value = f.version }
      # Bucket names are global in S3 — default to "{client}-{name}-{env}-web".
      "${k}-bucket" = { ws = k, key = "bucket_name", value = coalesce(f.bucket_name, "${k}-web") }
      "${k}-www"    = { ws = k, key = "www_redirect", value = try(f.www_redirect, false) ? "true" : "false" }
      # Derived here ("<name>.<zone>", or the zone root when serve_on_zone_root = true) and always
      # passed explicitly, so the same value feeds both the DNS records and the CORS origins.
      "${k}-domain" = { ws = k, key = "domain", value = f.resolved_domain }
    }
  ]...)

  workspace_id = tfe_workspace.frontend[each.value.ws].id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
}

resource "tfe_variable" "frontend_sans" {
  for_each = local.frontends

  workspace_id = tfe_workspace.frontend[each.key].id
  key          = "subject_alternative_names"
  value        = jsonencode(try(each.value.subject_alternative_names, []))
  category     = "terraform"
  hcl          = true
  description  = "Extra domains on the SPA distribution/cert (e.g. www)."
}

# Which APIs this SPA talks to. Documentation + tagging; the actual API URL is build-time config
# in the frontend repo.
resource "tfe_variable" "frontend_apps" {
  for_each = local.frontends

  workspace_id = tfe_workspace.frontend[each.key].id
  key          = "consumes_apps"
  value = jsonencode([
    for call in each.value.calls :
    try(call.source, null) == null
    ? call.backend
    : "${call.source.client}-${call.source.environment}/${call.backend}"
  ])
  category    = "terraform"
  hcl         = true
  description = "Backends this SPA calls (qualified as client-env/backend when they live elsewhere)."
}

# The frontend needs the zone, so it runs after its client-env's foundation.
resource "tfe_run_trigger" "frontend_after_foundation" {
  for_each = local.frontends

  workspace_id  = tfe_workspace.frontend[each.key].id
  sourceable_id = tfe_workspace.foundation[each.value.foundation_key].id
}

# ============================================================================
# AWS authentication: HCP dynamic provider credentials (OIDC). No long-lived keys —
# each workspace assumes `tfc_role_name` in ITS client-env's account. The role ARN is the
# thing that decides which AWS account a workspace deploys into, and it comes from
# clients.auto.tfvars. Each account must expose that role trusting app.terraform.io.
# ============================================================================
resource "tfe_variable" "foundation_aws_oidc" {
  for_each = merge([
    for k, c in local.foundations : {
      "${k}-auth" = { ws = k, key = "TFC_AWS_PROVIDER_AUTH", value = "true" }
      "${k}-role" = { ws = k, key = "TFC_AWS_RUN_ROLE_ARN", value = local.account_role_arn[k] }
    }
  ]...)

  workspace_id = tfe_workspace.foundation[each.value.ws].id
  key          = each.value.key
  value        = each.value.value
  category     = "env"
  description  = "HCP dynamic provider credentials (OIDC) — pins the AWS account."
}

resource "tfe_variable" "service_aws_oidc" {
  for_each = merge([
    for k, a in local.backends : {
      "${k}-auth" = { ws = k, key = "TFC_AWS_PROVIDER_AUTH", value = "true" }
      "${k}-role" = { ws = k, key = "TFC_AWS_RUN_ROLE_ARN", value = local.account_role_arn["${a.client}-${a.environment}"] }
    }
  ]...)

  workspace_id = tfe_workspace.service[each.value.ws].id
  key          = each.value.key
  value        = each.value.value
  category     = "env"
  description  = "HCP dynamic provider credentials (OIDC) — pins the AWS account."
}

resource "tfe_variable" "frontend_aws_oidc" {
  for_each = merge([
    for k, f in local.frontends : {
      "${k}-auth" = { ws = k, key = "TFC_AWS_PROVIDER_AUTH", value = "true" }
      "${k}-role" = { ws = k, key = "TFC_AWS_RUN_ROLE_ARN", value = local.account_role_arn[f.foundation_key] }
    }
  ]...)

  workspace_id = tfe_workspace.frontend[each.value.ws].id
  key          = each.value.key
  value        = each.value.value
  category     = "env"
  description  = "HCP dynamic provider credentials (OIDC) — pins the AWS account."
}

# Foundation applies trigger the client's service runs (keeps apply order sane).
resource "tfe_run_trigger" "service_after_foundation" {
  for_each = local.backends

  workspace_id  = tfe_workspace.service[each.key].id
  sourceable_id = tfe_workspace.foundation["${each.value.client}-${each.value.environment}"].id
}

# A provider foundation re-runs when a consumer foundation changes (so its RDS allowlist picks
# up a new/changed consumer NAT EIP). Consumer foundations must be applied FIRST on the initial
# bring-up — the provider reads their NAT EIP via remote state. Workspace names end in
# "-foundation"; strip it to index the foundation map.
resource "tfe_run_trigger" "provider_after_consumer" {
  for_each = local.provider_consumer_pairs

  workspace_id  = tfe_workspace.foundation[each.value[0].provider].id
  sourceable_id = tfe_workspace.foundation[each.value[0].consumer].id
}

# A consumer service re-runs when its external provider foundation changes (e.g. the shared
# db's password rotates), so it re-materializes the new connection string into its own SSM.
resource "tfe_run_trigger" "service_after_external_provider" {
  for_each = { for pair in flatten([
    for k, b in local.backends : [
      for p in distinct([
        for c in b.connections :
        "${c.source.client}-${c.source.environment}" if try(c.source, null) != null
      ]) : { app = k, provider = p }
    ]
  ]) : "${pair.app}<=${pair.provider}" => pair }

  workspace_id  = tfe_workspace.service[each.value.app].id
  sourceable_id = tfe_workspace.foundation[each.value.provider].id
}
