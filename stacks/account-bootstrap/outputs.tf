# Each must equal what the factory computes for that account: arn:aws:iam::<id>:role/tfc-deploy.
output "bootstrapped_role_arns" {
  description = "Account -> tfc-deploy role ARN created in it."
  value = {
    "sayer-prod"      = module.sayer_prod.role_arn
    "ulbrika-prod"    = module.ulbrika_prod.role_arn
    "ecolors-prod"    = module.ecolors_prod.role_arn
    "ecolors-nonprod" = module.ecolors_nonprod.role_arn
    "infrastructure"  = module.infrastructure.role_arn
  }
}
