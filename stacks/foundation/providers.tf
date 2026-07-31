provider "aws" {
  region = "us-east-1"

  # Guardrail: fail the plan if the run's credentials belong to another account.
  allowed_account_ids = var.aws_account_id != null ? [var.aws_account_id] : null

  default_tags {
    tags = {
      Client      = var.client
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "foundation"
    }
  }
}

# Cross-account provider for writing the NS delegation into the parent zone (ecolors.app).
# Assumes the dns-delegation role in the DNS-owning account. Only used when the delegation
# record has count > 0 (i.e. both dns_* variables are set), so a null role_arn is inert.
provider "aws" {
  alias  = "dns"
  region = "us-east-1"

  assume_role {
    role_arn = var.dns_delegation_role_arn
  }
}
