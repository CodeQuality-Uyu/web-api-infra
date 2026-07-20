output "zone_id" {
  value = local.effective_zone_id
}

output "zone_name" {
  value = var.zone_name
}

output "name_servers" {
  description = "Delegate these from your registrar (GoDaddy, etc.)."
  value       = try(aws_route53_zone.this[0].name_servers, [])
}
