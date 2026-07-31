# =============================================================================================
# Organization structure — ENVIRONMENT-FIRST (see docs/adr/0008). OUs exist to apply SCPs, so
# they group by what shares policy = environment. Tenant isolation lives at the ACCOUNT level.
#
#   Root
#   ├── Security         (future: log-archive + audit accounts)
#   ├── Infrastructure   (future: shared DNS / network account)
#   ├── Workloads
#   │   ├── Prod         → prod SCP applies to every tenant's prod account
#   │   └── NonProd      → nonprod SCP
#   └── Suspended        → restrictive SCP; decommissioned/old accounts land here
#
# Accounts are named <client>-<env> and placed under Workloads/<env>. Tenant is tracked by the
# `Tenant` tag, not by the OU tree. The old per-tenant OUs (EColors/Sayer/Ulbrika) and their old
# accounts are NOT managed here — they're decommissioned by hand (move to Suspended, then close).
#
# ⚠️ Accounts are effectively PERMANENT: destroy tries to CLOSE them (90-day suspension). Every
# account has prevent_destroy. Root emails are unique and immutable.
# =============================================================================================

# The organization itself is MANAGED here so we can enable the policy types we use.
# It already exists → import it once:  terraform import aws_organizations_organization.this o-kf9lzgx3ia
# (feature_set ALL is what an org with OUs/SCPs already has.)
resource "aws_organizations_organization" "this" {
  feature_set = "ALL"
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
  ]
}

locals {
  root_id = aws_organizations_organization.this.roots[0].id

  # (client, env) pairs keyed "client-env".
  vend_envs = merge([
    for c in var.clients_to_vend : {
      for e in c.environments : "${c.client}-${e.env}" => { client = c.client, env = e.env, email = e.email }
    }
  ]...)
}

# Top-level foundational OUs, always present (they frame the org even before accounts exist).
resource "aws_organizations_organizational_unit" "foundational" {
  for_each = toset(["Security", "Infrastructure", "Workloads", "Suspended"])

  name      = each.value
  parent_id = local.root_id
}

# Environment OUs under Workloads — this is where the per-environment SCPs attach.
resource "aws_organizations_organizational_unit" "environment" {
  for_each = var.workload_environments # { prod = "Prod", nonprod = "NonProd" }

  name      = each.value
  parent_id = aws_organizations_organizational_unit.foundational["Workloads"].id
}

resource "aws_organizations_account" "this" {
  for_each = local.vend_envs

  name      = "${each.value.client}-${each.value.env}" # sayer-prod, ecolors-nonprod, ...
  email     = each.value.email
  parent_id = aws_organizations_organizational_unit.environment[each.value.env].id

  role_name         = "OrganizationAccountAccessRole"
  close_on_deletion = false

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [role_name]
  }

  tags = { Tenant = each.value.client, Environment = each.value.env, ManagedBy = "terraform" }
}

# Platform accounts (infrastructure, finops, log-archive, ...) under a foundational OU.
resource "aws_organizations_account" "platform" {
  for_each = { for a in var.platform_accounts : a.name => a }

  name      = each.value.name
  email     = each.value.email
  parent_id = aws_organizations_organizational_unit.foundational[each.value.ou].id

  role_name         = "OrganizationAccountAccessRole"
  close_on_deletion = false

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [role_name]
  }

  tags = { Platform = each.value.name, ManagedBy = "terraform" }
}
