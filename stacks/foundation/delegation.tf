# Automatic NS delegation: write THIS zone's name servers into the parent zone (ecolors.app),
# cross-account, so onboarding a client delegates its subdomain with no manual step. Only runs
# when the factory provided both dns_* variables AND this foundation created its own zone.
locals {
  delegate_dns = var.dns_parent_zone_id != null && var.dns_delegation_role_arn != null && length(module.dns.name_servers) > 0
}

resource "aws_route53_record" "delegation" {
  count    = local.delegate_dns ? 1 : 0
  provider = aws.dns

  zone_id = var.dns_parent_zone_id
  name    = var.zone_name # e.g. sayer.ecolors.app — a subdomain of the parent zone
  type    = "NS"
  ttl     = 300
  records = module.dns.name_servers
}
