terraform {
  required_version = ">= 1.5.0"

  # NOTE: no `cloud {}` block on purpose. This stack CREATES the OIDC role that every other
  # workspace assumes, so it cannot be deployed via that same OIDC (chicken-and-egg). Apply it
  # ONCE per AWS account with elevated credentials — typically locally with your IAM Identity
  # Center (SSO) admin session, using local state. See stacks/bootstrap/README.md.

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
