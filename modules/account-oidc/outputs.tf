output "role_arn" {
  description = "ARN of the tfc-deploy role. Must equal what the factory computes: arn:aws:iam::<account>:role/<role_name>."
  value       = aws_iam_role.tfc_deploy.arn
}

output "role_name" {
  value = aws_iam_role.tfc_deploy.name
}

output "tfc_oidc_provider_arn" {
  value = local.tfc_provider_arn
}
