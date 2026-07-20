output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "db_clients_sg_id" {
  value = module.network.db_clients_sg_id
}

output "bastion_sg_id" {
  value = module.network.bastion_sg_id
}

output "bastion_instance_id" {
  value = module.network.bastion_instance_id
}

output "nat_eip" {
  description = "Public egress IP of this VPC. A provider client-env allowlists it on its public RDS."
  value       = module.network.nat_eip
}

output "zone_id" {
  value = module.dns.zone_id
}

output "zone_name" {
  value = module.dns.zone_name
}

output "name_servers" {
  description = "Delegate these from your registrar."
  value       = module.dns.name_servers
}

output "github_oidc_provider_arn" {
  value = var.enable_github_oidc ? aws_iam_openid_connect_provider.github[0].arn : null
}

output "ecr_repository_urls" {
  description = "Map app slug -> ECR repository URL (no tag). Service composes image_uri as <url>:<version>."
  value       = module.ecr.repository_urls
}

# --- Shared RDS (consumed by every service stack for this client-env) ---
output "db_address" {
  value = module.database.db_address
}

output "db_port" {
  value = module.database.db_port
}

output "db_connection_string_arns" {
  description = "Map db_name -> SSM SecureString ARN. Service picks its app's db by its explicit db_name."
  value       = module.database.connection_string_arns
}

output "db_connection_string_names" {
  description = "Map db_name -> SSM parameter name. Passed to the migration job so it reads the right connection string."
  value       = module.database.connection_string_names
}

output "db_connection_string_kms_key_arn" {
  value = module.database.connection_string_kms_key_arn
}

# Full connection string VALUES (sensitive). Consumed by service stacks in OTHER accounts via
# remote state (they re-store it in their own SSM). Only useful when db_public = true.
output "db_connection_strings" {
  description = "Map db_name -> connection string value. Sensitive; for cross-account consumers."
  value       = module.database.connection_strings
  sensitive   = true
}
