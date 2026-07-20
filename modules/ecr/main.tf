# One ECR repository per app, named "{client}-{app}-{env}" (passed in via var.repositories).
# Tags are IMMUTABLE by default so a version (e.g. :1.4.0) is a permanent, unambiguous
# artifact — the service pins a version and Terraform promotes it deliberately.
resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name                 = each.value
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, { App = each.key })
}

# Keep the registry tidy: drop untagged layers left behind by re-pushes.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after 14 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 14
      }
      action = { type = "expire" }
    }]
  })
}
