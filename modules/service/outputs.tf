output "service_arn" {
  value = aws_apprunner_service.this.arn
}

output "service_default_url" {
  description = "App Runner's own URL (works before the custom domain resolves)."
  value       = aws_apprunner_service.this.service_url
}

output "app_url" {
  value = "https://${var.domain_fqdn}"
}

output "instance_role_arn" {
  value = aws_iam_role.instance.arn
}
