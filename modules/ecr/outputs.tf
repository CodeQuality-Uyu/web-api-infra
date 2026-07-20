output "repository_urls" {
  description = "Map app slug -> repository URL (host/name, no tag). Service composes image_uri as <url>:<version>."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  value = { for k, r in aws_ecr_repository.this : k => r.arn }
}

output "repository_names" {
  value = { for k, r in aws_ecr_repository.this : k => r.name }
}
