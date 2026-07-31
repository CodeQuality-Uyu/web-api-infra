terraform {
  required_version = ">= 1.5.0"

  # Runs in the MANAGEMENT account as tfc-org-admin (created by stacks/bootstrap, Fase 0). It
  # assumes each child account's OrganizationAccountAccessRole and stands up that account's
  # tfc-deploy role — automating the per-account bootstrap so it isn't a manual, per-account run.
  # One HCP workspace tagged `account-bootstrap`.
  cloud {
    organization = "ColorLabs"
    workspaces {
      tags = ["account-bootstrap"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}
