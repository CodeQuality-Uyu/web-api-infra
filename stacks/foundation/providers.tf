provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Client      = var.client
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "foundation"
    }
  }
}
