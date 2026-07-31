# One tfc-deploy role per account, created THROUGH the assumed OrganizationAccountAccessRole.
# All use the `workload` profile (the management account got `org-admin` back in Fase 0). Same
# module the manual per-account bootstrap uses — this just drives it for every account at once.

module "sayer_prod" {
  source           = "../../modules/account-oidc"
  providers        = { aws = aws.sayer_prod }
  tfc_organization = var.tfc_organization
  tags             = { Account = "sayer-prod", ManagedBy = "terraform" }
}

module "ulbrika_prod" {
  source           = "../../modules/account-oidc"
  providers        = { aws = aws.ulbrika_prod }
  tfc_organization = var.tfc_organization
  tags             = { Account = "ulbrika-prod", ManagedBy = "terraform" }
}

module "ecolors_prod" {
  source           = "../../modules/account-oidc"
  providers        = { aws = aws.ecolors_prod }
  tfc_organization = var.tfc_organization
  tags             = { Account = "ecolors-prod", ManagedBy = "terraform" }
}

module "ecolors_nonprod" {
  source           = "../../modules/account-oidc"
  providers        = { aws = aws.ecolors_nonprod }
  tfc_organization = var.tfc_organization
  tags             = { Account = "ecolors-nonprod", ManagedBy = "terraform" }
}

module "infrastructure" {
  source           = "../../modules/account-oidc"
  providers        = { aws = aws.infrastructure }
  tfc_organization = var.tfc_organization
  tags             = { Account = "infrastructure", ManagedBy = "terraform" }
}
