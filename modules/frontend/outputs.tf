output "bucket_name" {
  description = "S3 bucket the FE CI syncs the build into."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "distribution_id" {
  description = "CloudFront distribution id — the FE CI invalidates this after a deploy."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  value = aws_cloudfront_distribution.this.arn
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "url" {
  value = "https://${var.domain_fqdn}"
}
