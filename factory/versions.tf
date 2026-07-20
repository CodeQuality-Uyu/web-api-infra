terraform {
  required_version = ">= 1.5.0"
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = ">= 0.55"
    }
  }
}

provider "tfe" {
  organization = var.organization
  # Auth via TFE_TOKEN env var.
}
