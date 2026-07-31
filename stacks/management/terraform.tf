terraform {
  required_version = ">= 1.5.0"

  # Deployed in the MANAGEMENT (root) account, which governs the Organization, IAM Identity
  # Center and billing — it holds NO workloads. Assumes the `tfc-org-admin` role (org-admin
  # profile), NOT the workload `tfc-deploy`. A single, manually-created HCP workspace points
  # here; it is not stamped by the factory (the root is not a client-env).
  cloud {
    organization = "ColorLabs"
    workspaces {
      tags = ["management"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
