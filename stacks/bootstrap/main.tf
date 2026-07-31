# One-time-per-account baseline: the OIDC federation + the tfc-deploy role that every other
# workspace in this account assumes. After this runs once, nothing else needs static AWS keys.
module "oidc" {
  source = "../../modules/account-oidc"

  role_name                = var.role_name
  profile                  = var.role_profile
  tfc_organization         = var.tfc_organization
  tfc_allowed_subs         = var.tfc_allowed_subs
  create_tfc_oidc_provider = var.create_tfc_oidc_provider
  tags                     = var.tags
}
