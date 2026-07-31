# Account ids come from the management stack's outputs — nothing is hardcoded.
data "terraform_remote_state" "management" {
  backend = "remote"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = var.management_workspace
    }
  }
}

locals {
  vended   = data.terraform_remote_state.management.outputs.vended_account_ids   # "client-env" => id
  platform = data.terraform_remote_state.management.outputs.platform_account_ids # "name"       => id
}

# Base identity: this workspace runs as tfc-org-admin in the management account. It is only used
# to assume OrganizationAccountAccessRole into each child below (no resources use it directly).
provider "aws" {
  region = "us-east-1"
}

# --- One aliased provider per account: assume its OrganizationAccountAccessRole -------------------
# Provider aliases can't be generated dynamically, so there is one block per account. Adding an
# account = add its block here + a module call in main.tf. allowed_account_ids double-checks the
# assume-role landed in the intended account.

provider "aws" {
  alias               = "sayer_prod"
  region              = "us-east-1"
  allowed_account_ids = [local.vended["sayer-prod"]]
  assume_role { role_arn = "arn:aws:iam::${local.vended["sayer-prod"]}:role/${var.org_account_role}" }
}

provider "aws" {
  alias               = "ulbrika_prod"
  region              = "us-east-1"
  allowed_account_ids = [local.vended["ulbrika-prod"]]
  assume_role { role_arn = "arn:aws:iam::${local.vended["ulbrika-prod"]}:role/${var.org_account_role}" }
}

provider "aws" {
  alias               = "ecolors_prod"
  region              = "us-east-1"
  allowed_account_ids = [local.vended["ecolors-prod"]]
  assume_role { role_arn = "arn:aws:iam::${local.vended["ecolors-prod"]}:role/${var.org_account_role}" }
}

provider "aws" {
  alias               = "ecolors_nonprod"
  region              = "us-east-1"
  allowed_account_ids = [local.vended["ecolors-nonprod"]]
  assume_role { role_arn = "arn:aws:iam::${local.vended["ecolors-nonprod"]}:role/${var.org_account_role}" }
}

# Platform account that runs Terraform (holds the parent DNS zone). finops has no workspaces yet,
# so it isn't bootstrapped; add a block + module call when it needs to deploy.
provider "aws" {
  alias               = "infrastructure"
  region              = "us-east-1"
  allowed_account_ids = [local.platform["infrastructure"]]
  assume_role { role_arn = "arn:aws:iam::${local.platform["infrastructure"]}:role/${var.org_account_role}" }
}
