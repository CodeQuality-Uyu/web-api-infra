provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Client      = var.client
      App         = var.app
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "service"
    }
  }
}

# CloudFront ACM certs must live in us-east-1 (only used by the optional blobs module).
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
