provider "aws" {
  region = "us-east-1"
  allowed_account_ids = [var.aws_account_id]
  default_tags {
    tags = {
      ManagedBy = "terraform"
      Stack     = "infrastructure"
    }
  }
}

# The shared parent zone. GoDaddy delegates <parent_zone_name> to THIS zone's name servers
# (one-time, manual, at the registrar). Client foundations then delegate their own subdomains
# into it via the dns-delegation role below.
resource "aws_route53_zone" "parent" {
  count = var.create_parent_zone ? 1 : 0
  name  = var.parent_zone_name
}

locals {
  parent_zone_id = var.create_parent_zone ? aws_route53_zone.parent[0].zone_id : var.parent_zone_id
}

# The cross-account delegation role client foundations assume to write their NS records here.
module "dns_delegation_role" {
  source = "../../modules/dns-delegation-role"

  hosted_zone_id = local.parent_zone_id
  org_id         = var.org_id
}

output "parent_zone_id" {
  description = "Set this as dns_parent_zone_id in the factory."
  value       = local.parent_zone_id
}

output "parent_zone_name_servers" {
  description = "Delegate the parent domain to these at the registrar (GoDaddy), one time."
  value       = try(aws_route53_zone.parent[0].name_servers, [])
}

output "dns_delegation_role_arn" {
  value = module.dns_delegation_role.role_arn
}
