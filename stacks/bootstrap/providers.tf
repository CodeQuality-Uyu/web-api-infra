provider "aws" {
  region = "us-east-1"

  # Guardrail: fail if the credentials used to bootstrap belong to a different account.
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
