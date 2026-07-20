terraform {
  required_version = ">= 1.5.0"

  # HCP Terraform (Terraform Cloud). Set the org via TF_CLOUD_ORGANIZATION or edit here.
  # Foundation workspaces are tagged "foundation"; the factory creates one per client.
  cloud {
    organization = "REPLACE_ORG"
    workspaces {
      tags = ["foundation"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}
