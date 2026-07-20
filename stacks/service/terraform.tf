terraform {
  required_version = ">= 1.5.0"

  cloud {
    organization = "REPLACE_ORG"
    workspaces {
      tags = ["service"]
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
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
