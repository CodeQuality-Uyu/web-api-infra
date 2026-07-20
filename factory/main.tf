# ============================================================================
# Client factory: one definition (clients.auto.tfvars) -> all workspaces + vars.
# Onboarding a client = a foundation workspace; onboarding an app = a service
# workspace with a run-trigger from its client's foundation.
# ============================================================================

locals {
  foundations = { for c in var.clients : "${c.client}-${c.environment}" => c }

  apps = merge([
    for c in var.clients : {
      for a in c.apps :
      "${c.client}-${a.app}-${c.environment}" => merge(a, {
        client      = c.client
        environment = c.environment
        foundation  = "${c.client}-${c.environment}-foundation"
      })
    }
  ]...)

  # --- Cross-env shared-DB topology ---------------------------------------------------------
  # Every connection with `source` = a consumer foundation depending on a provider foundation.
  external_links = flatten([
    for k, a in local.apps : [
      for c in a.connections : {
        provider = c.source        # provider foundation workspace name
        consumer = a.foundation    # consumer foundation workspace name
      } if try(c.source, null) != null
    ]
  ])

  # provider foundation workspace name -> distinct consumer foundation workspace names.
  db_providers = {
    for p in distinct([for l in local.external_links : l.provider]) :
    p => distinct([for l in local.external_links : l.consumer if l.provider == p])
  }

  # Distinct (provider, consumer) pairs, for run-trigger ordering.
  provider_consumer_pairs = {
    for l in local.external_links : "${l.provider}<=${l.consumer}" => l...
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

  vcs_repo {
    identifier     = var.vcs_identifier
    branch         = var.version_tag
    oauth_token_id = var.oauth_token_id
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
      "${k}-region"      = { ws = k, key = "aws_region", value = var.aws_region }
      "${k}-zone"        = { ws = k, key = "zone_name", value = c.zone_name }
      "${k}-org"         = { ws = k, key = "tfc_organization", value = var.organization }
      # Provider flag: is any db of this client-env referenced externally?
      "${k}-db_public" = { ws = k, key = "db_public", value = contains(keys(local.db_providers), "${k}-foundation") ? "true" : "false" }
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
  value        = jsonencode([for a in each.value.apps : a.app])
  category     = "terraform"
  hcl          = true
  description  = "App slugs; foundation creates one ECR repo ({client}-{app}-{env}) per app."
}

# The union of every db_name referenced by this client-env's apps → one database each on the
# shared RDS (created once even if multiple apps connect to it).
resource "tfe_variable" "foundation_databases" {
  for_each = local.foundations

  workspace_id = tfe_workspace.foundation[each.key].id
  key          = "databases"
  # Only LOCAL connections (no `source`) — a `source` db lives in another client-env's RDS, so
  # this foundation must not create a duplicate for it.
  value       = jsonencode(distinct(flatten([for a in each.value.apps : [for c in a.connections : c.db_name if try(c.source, null) == null]])))
  category    = "terraform"
  hcl         = true
  description = "Distinct LOCAL database names (connections without `source`). Foundation creates one per name."
}

# Consumer foundations (other client-envs) whose NAT EIPs this provider must allowlist.
resource "tfe_variable" "foundation_consumers" {
  for_each = local.foundations

  workspace_id = tfe_workspace.foundation[each.key].id
  key          = "db_consumer_workspaces"
  value        = jsonencode(try(local.db_providers["${each.key}-foundation"], []))
  category     = "terraform"
  hcl          = true
  description  = "Consumer foundation workspace names; their NAT EIPs are allowlisted on the public RDS."
}

# --- Service workspaces (one per app) ---
resource "tfe_workspace" "service" {
  for_each = local.apps

  name              = "${each.key}-service"
  organization      = var.organization
  tag_names         = ["service"]
  working_directory = "stacks/service"
  auto_apply        = false

  vcs_repo {
    identifier     = var.vcs_identifier
    branch         = var.version_tag
    oauth_token_id = var.oauth_token_id
  }
}

resource "tfe_variable" "service" {
  for_each = merge([
    for k, a in local.apps : {
      "${k}-client"       = { ws = k, key = "client", value = a.client }
      "${k}-app"          = { ws = k, key = "app", value = a.app }
      "${k}-environment"  = { ws = k, key = "environment", value = a.environment }
      "${k}-region"       = { ws = k, key = "aws_region", value = var.aws_region }
      "${k}-org"          = { ws = k, key = "tfc_organization", value = var.organization }
      "${k}-foundation"   = { ws = k, key = "foundation_workspace", value = a.foundation }
      "${k}-version"      = { ws = k, key = "image_version", value = a.version }
      "${k}-subdomain"    = { ws = k, key = "subdomain", value = a.subdomain }
      "${k}-github_repo"  = { ws = k, key = "github_repo", value = a.github_repo }
    }
  ]...)

  workspace_id = tfe_workspace.service[each.value.ws].id
  key          = each.value.key
  value        = each.value.value
  category     = "terraform"
}

# HCL-typed service vars (a map / a list). Plaintext app config + the NAMES of secret env
# vars. Secret VALUES are never set here — they go in the workspace's sensitive `secret_values`.
resource "tfe_variable" "service_settings" {
  for_each = local.apps

  workspace_id = tfe_workspace.service[each.key].id
  key          = "runtime_env"
  value        = jsonencode(each.value.settings)
  category     = "terraform"
  hcl          = true
  description  = ".NET-style env vars (Key__Child) injected into App Runner; overrides appsettings.json."
}

resource "tfe_variable" "service_secret_settings" {
  for_each = local.apps

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
  for_each = local.apps

  workspace_id = tfe_workspace.service[each.key].id
  key          = "connections"
  value        = jsonencode(each.value.connections)
  category     = "terraform"
  hcl          = true
  description  = "DB connections for this app. Exactly one migrate=true (its own database)."
}

# Foundation applies trigger the client's service runs (keeps apply order sane).
resource "tfe_run_trigger" "service_after_foundation" {
  for_each = local.apps

  workspace_id  = tfe_workspace.service[each.key].id
  sourceable_id = tfe_workspace.foundation["${each.value.client}-${each.value.environment}"].id
}

# A provider foundation re-runs when a consumer foundation changes (so its RDS allowlist picks
# up a new/changed consumer NAT EIP). Consumer foundations must be applied FIRST on the initial
# bring-up — the provider reads their NAT EIP via remote state. Workspace names end in
# "-foundation"; strip it to index the foundation map.
resource "tfe_run_trigger" "provider_after_consumer" {
  for_each = local.provider_consumer_pairs

  workspace_id  = tfe_workspace.foundation[trimsuffix(each.value[0].provider, "-foundation")].id
  sourceable_id = tfe_workspace.foundation[trimsuffix(each.value[0].consumer, "-foundation")].id
}

# A consumer service re-runs when its external provider foundation changes (e.g. the shared
# db's password rotates), so it re-materializes the new connection string into its own SSM.
resource "tfe_run_trigger" "service_after_external_provider" {
  for_each = { for pair in flatten([
    for k, a in local.apps : [
      for s in distinct([for c in a.connections : c.source if try(c.source, null) != null]) :
      { app = k, source = s }
    ]
  ]) : "${pair.app}<=${pair.source}" => pair }

  workspace_id  = tfe_workspace.service[each.value.app].id
  sourceable_id = tfe_workspace.foundation[trimsuffix(each.value.source, "-foundation")].id
}
