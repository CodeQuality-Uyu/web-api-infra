provider "aws" {
  region = "us-east-1"

  # Guardrail: fail the plan if the run's credentials belong to another account.
  allowed_account_ids = var.aws_account_id != null ? [var.aws_account_id] : null

  default_tags {
    tags = {
      Client      = var.client
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "frontend"
    }
  }
}

# CloudFront requires its ACM certificate in us-east-1.
provider "aws" {
  alias               = "us_east_1"
  region              = "us-east-1"
  allowed_account_ids = var.aws_account_id != null ? [var.aws_account_id] : null
}
