provider "aws" {
  region = "us-east-1"

  # Guardrail: this must run in the management account, never a member account.
  allowed_account_ids = [var.management_account_id]

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Stack     = "management"
    }
  }
}
