# The role GitHub Actions assumes (via OIDC, no static keys) to publish artifacts:
#   - push backend images to ECR (repos are created by the foundation — NOT here),
#   - sync frontend builds into the FE S3 buckets and invalidate CloudFront.
# Parallel to tfc-deploy: same account, but for GitHub instead of HCP Terraform.

# Trust: only the listed repos, only their main branch and tags.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = flatten([
        for r in var.github_repos : [
          "repo:${r}:ref:refs/heads/main",
          "repo:${r}:ref:refs/tags/*",
        ]
      ])
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = "GitHub Actions deploy role (ECR push + FE S3 sync). Repos: ${join(", ", var.github_repos)}."
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
  tags                 = var.tags
}

data "aws_iam_policy_document" "perms" {
  # ECR login token is account-wide by AWS design.
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push (and pull) images — but NOT create/delete repositories: the foundation owns those.
  dynamic "statement" {
    for_each = length(var.ecr_repository_arns) > 0 ? [1] : []
    content {
      sid    = "EcrPush"
      effect = "Allow"
      actions = [
        "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer", "ecr:DescribeRepositories", "ecr:ListImages",
      ]
      resources = var.ecr_repository_arns
    }
  }

  # Frontend deploy: sync objects into the FE buckets.
  dynamic "statement" {
    for_each = length(var.frontend_bucket_arns) > 0 ? [1] : []
    content {
      sid       = "S3List"
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = var.frontend_bucket_arns
    }
  }
  dynamic "statement" {
    for_each = length(var.frontend_bucket_arns) > 0 ? [1] : []
    content {
      sid       = "S3Objects"
      effect    = "Allow"
      actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
      resources = [for a in var.frontend_bucket_arns : "${a}/*"]
    }
  }

  # CloudFront invalidation. Distribution ARNs aren't known here, so scoped to the action only.
  statement {
    sid       = "CloudFrontInvalidate"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.role_name}-deploy"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.perms.json
}
