output "bucket_name" {
  value = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "cloudfront_domain" {
  value = "https://${var.domain_fqdn}"
}
