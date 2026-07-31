output "role_arn" {
  description = "ARN of the tfc-deploy role. The factory expects exactly this: arn:aws:iam::<account>:role/tfc-deploy."
  value       = module.oidc.role_arn
}

output "tfc_oidc_provider_arn" {
  value = module.oidc.tfc_oidc_provider_arn
}
