# When this client-env's RDS is shared (db_public), read each consumer client-env's
# foundation to learn its public egress IP (NAT EIP), and allowlist it on the RDS SG.
# Cross-account is fine: terraform_remote_state reads at the HCP org level, not AWS.
# Consumer foundations must be applied first (their NAT EIP must already exist).
data "terraform_remote_state" "consumer" {
  for_each = var.db_public ? toset(var.db_consumer_workspaces) : []

  backend = "remote"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = each.value
    }
  }
}

locals {
  # /32 CIDRs of every consumer's NAT EIP (skip any not yet applied / without NAT).
  consumer_cidrs = [
    for s in data.terraform_remote_state.consumer :
    "${s.outputs.nat_eip}/32" if try(s.outputs.nat_eip, null) != null
  ]
}
