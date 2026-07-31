terraform {
  required_version = ">= 1.5.0"

  # HCP Terraform. Frontend workspaces are tagged "frontend"; the factory creates one per
  # client-env that declares a `frontend` block.
  cloud {
    organization = "REPLACE_ORG"
    workspaces {
      tags = ["frontend"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
