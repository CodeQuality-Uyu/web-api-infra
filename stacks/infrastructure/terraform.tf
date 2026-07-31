terraform {
  required_version = ">= 1.5.0"

  # Runs in the dedicated INFRASTRUCTURE account (shared platform services). Holds the parent
  # DNS zone (ecolors.app) and the cross-account delegation role. Deployed via that account's
  # tfc-deploy (bootstrap it first). One HCP workspace tagged `infrastructure`.
  cloud {
    organization = "ColorLabs"
    workspaces {
      tags = ["infrastructure"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
