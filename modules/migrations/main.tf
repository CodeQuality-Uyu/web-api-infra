data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  project_name = "${var.name}-migrate"
}

# --- CodeBuild service role ---
data "aws_iam_policy_document" "cb_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${local.project_name}-role"
  assume_role_policy = data.aws_iam_policy_document.cb_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }

  # Required for running the build inside a VPC.
  statement {
    sid = "VpcEni"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "VpcEniPermission"
    actions   = ["ec2:CreateNetworkInterfacePermission"]
    resources = ["arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:AuthorizedService"
      values   = ["codebuild.amazonaws.com"]
    }
  }

  dynamic "statement" {
    for_each = length(var.secret_source_arns) > 0 ? [1] : []
    content {
      sid       = "ReadDbSecret"
      actions   = ["ssm:GetParameters", "ssm:GetParameter", "secretsmanager:GetSecretValue"]
      resources = var.secret_source_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.kms_key_arns) > 0 ? [1] : []
    content {
      sid       = "Decrypt"
      actions   = ["kms:Decrypt"]
      resources = var.kms_key_arns
    }
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "${local.project_name}-policy"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild.json
}

# --- CodeBuild project (runs inside the VPC, reaches RDS directly) ---
resource "aws_codebuild_project" "this" {
  name         = local.project_name
  service_role = aws_iam_role.codebuild.arn

  artifacts { type = "NO_ARTIFACTS" }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = var.codebuild_image
    type            = "LINUX_CONTAINER"
    privileged_mode = false

    dynamic "environment_variable" {
      for_each = var.env
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }

  source {
    type      = "GITHUB"
    location  = "https://github.com/${var.github_repo}.git"
    buildspec = var.buildspec
  }
  source_version = var.github_branch

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  tags = var.tags
}

# --- CI role the app's GitHub Action assumes (OIDC) to start the migration ---
data "aws_iam_policy_document" "ci_assume" {
  statement {
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
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "${local.project_name}-ci"
  assume_role_policy = data.aws_iam_policy_document.ci_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "ci" {
  statement {
    sid       = "StartMigration"
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = [aws_codebuild_project.this.arn]
  }
}

resource "aws_iam_role_policy" "ci" {
  name   = "${local.project_name}-ci-policy"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci.json
}
