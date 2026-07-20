output "app_url" {
  value = module.service.app_url
}

output "app_runner_default_url" {
  value = module.service.service_default_url
}

output "db_endpoint" {
  description = "Shared RDS endpoint (from foundation)."
  value       = local.f.db_address
}

output "migration_ci_role_arn" {
  description = "Role the app's GitHub Action assumes to run migrations."
  value       = module.migrations.ci_role_arn
}

output "migration_codebuild_project" {
  value = module.migrations.codebuild_project_name
}

output "blobs_cloudfront_domain" {
  value = var.create_blobs ? module.blobs[0].cloudfront_domain : null
}
