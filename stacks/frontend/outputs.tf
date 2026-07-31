output "url" {
  description = "Public SPA URL (the zone apex)."
  value       = module.frontend.url
}

output "bucket_name" {
  description = "Bucket the FE CI syncs the build into."
  value       = module.frontend.bucket_name
}

output "distribution_id" {
  description = "CloudFront distribution id — invalidate its cache (\"/*\") after bumping release_version to make the cutover/rollback instant."
  value       = module.frontend.distribution_id
}

output "invalidate_command" {
  description = "Ready-to-run cache invalidation for the promote/rollback step."
  value       = "aws cloudfront create-invalidation --distribution-id ${module.frontend.distribution_id} --paths '/*'"
}

output "cloudfront_domain" {
  value = module.frontend.cloudfront_domain
}

output "release_version" {
  value = var.release_version
}

output "release_date" {
  description = "When release_version was last bumped."
  value       = time_static.release.rfc3339
}
