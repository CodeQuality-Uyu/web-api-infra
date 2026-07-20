# The client's hosted zone. App Runner issues its own TLS cert per app domain, so
# this module only owns the zone + name servers (delegate these from your registrar).
resource "aws_route53_zone" "this" {
  count   = var.create_zone && var.zone_id == null ? 1 : 0
  name    = var.zone_name
  comment = "Public hosted zone for ${var.zone_name}"
  tags    = merge(var.tags, { Name = "${var.name}-zone" })
}

locals {
  effective_zone_id = coalesce(var.zone_id, try(aws_route53_zone.this[0].zone_id, null))
}
