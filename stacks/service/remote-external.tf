# Cross-env shared databases. A connection with `source` points at another client-env's
# foundation (possibly in another AWS account) whose RDS is public. We read that foundation's
# connection string VALUE via HCP remote state (org-level, cross-account is fine) and re-store
# it in THIS account's SSM SecureString so App Runner can inject it as a runtime secret.
locals {
  external_conns = [for c in var.connections : c if try(c.source, null) != null]
  local_conns    = [for c in var.connections : c if try(c.source, null) == null]

  external_sources = distinct([for c in local.external_conns : c.source])
}

data "terraform_remote_state" "external" {
  for_each = toset(local.external_sources)

  backend = "remote"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = each.value
    }
  }
}

# One SSM SecureString per external connection, holding the provider's connection string value.
resource "aws_ssm_parameter" "external_conn" {
  for_each = { for c in local.external_conns : c.key => c }

  name  = "/app/${var.environment}/external/${local.name}/${each.key}"
  type  = "SecureString"
  value = data.terraform_remote_state.external[each.value.source].outputs.db_connection_strings[each.value.db_name]
  tags  = local.tags
}
