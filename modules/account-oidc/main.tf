# =============================================================================================
# Federation for HCP Terraform (OIDC): the `tfc-deploy` role each workspace assumes to deploy,
# with NO long-lived AWS keys. Ported from EColors' documented `TerraformDeploymentRole-*`, with
# two deliberate changes:
#   1. Permissions target THIS platform (App Runner, not ECS), and allow the IAM role management
#      our stacks do — the documented guardrails denied that because ECS roles were pre-created.
#   2. Guardrails still deny the dangerous surface (users, org, billing) AND self-tampering.
# Applied once per AWS account (see stacks/bootstrap).
# =============================================================================================

data "aws_caller_identity" "current" {}

# --- OIDC provider for app.terraform.io ---
# Thumbprint fetched dynamically from the live cert chain (robust to rotations).
data "tls_certificate" "tfc" {
  count = var.create_tfc_oidc_provider ? 1 : 0
  url   = "https://app.terraform.io"
}

resource "aws_iam_openid_connect_provider" "tfc" {
  count = var.create_tfc_oidc_provider ? 1 : 0

  url             = "https://app.terraform.io"
  client_id_list  = ["aws.workload.identity"]
  thumbprint_list = [data.tls_certificate.tfc[0].certificates[length(data.tls_certificate.tfc[0].certificates) - 1].sha1_fingerprint]
  tags            = merge(var.tags, { Name = "app.terraform.io" })
}

# Use the created provider, or look up the existing one.
data "aws_iam_openid_connect_provider" "tfc" {
  count = var.create_tfc_oidc_provider ? 0 : 1
  url   = "https://app.terraform.io"
}

locals {
  tfc_provider_arn = var.create_tfc_oidc_provider ? aws_iam_openid_connect_provider.tfc[0].arn : data.aws_iam_openid_connect_provider.tfc[0].arn
  allowed_subs     = coalesce(var.tfc_allowed_subs, ["organization:${var.tfc_organization}:project:*:workspace:*:run_phase:*"])
}

# --- The role HCP Terraform assumes ---
data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "AllowTerraformCloudToAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.tfc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "app.terraform.io:aud"
      values   = ["aws.workload.identity"]
    }
    condition {
      test     = "StringLike"
      variable = "app.terraform.io:sub"
      values   = local.allowed_subs
    }
  }
}

resource "aws_iam_role" "tfc_deploy" {
  name                 = var.role_name
  description          = "HCP Terraform (app.terraform.io) deploys this platform via OIDC. Scoped to org ${var.tfc_organization}."
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
  tags                 = var.tags
}

# --- Guardrails: ALLOW what the stacks actually use ---
data "aws_iam_policy_document" "allow" {
  statement {
    sid    = "CoreInfra"
    effect = "Allow"
    actions = [
      "ec2:*", "rds:*", "apprunner:*", "ecr:*", "s3:*", "cloudfront:*",
      "acm:*", "route53:*", "ssm:*", "secretsmanager:*", "logs:*",
      "codebuild:*", "cloudwatch:*", "scheduler:*", "sts:GetCallerIdentity", "tag:*",
    ]
    resources = ["*"]
  }

  # Scoped KMS: enough to use the AWS-managed aws/ssm key for SecureString, not manage keys.
  statement {
    sid    = "KmsUse"
    effect = "Allow"
    actions = [
      "kms:DescribeKey", "kms:CreateGrant", "kms:Decrypt", "kms:Encrypt",
      "kms:GenerateDataKey", "kms:ListAliases",
    ]
    resources = ["*"]
  }

  # Our stacks CREATE IAM roles (App Runner access/instance, CodeBuild, migrations CI, bastion)
  # and the GitHub OIDC provider. Allow role/policy/instance-profile/OIDC management.
  statement {
    sid    = "WorkloadIamManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:ListRoles", "iam:UpdateRole",
      "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags", "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion",
      "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:ListPolicyVersions",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile",
      "iam:CreateOpenIDConnectProvider", "iam:GetOpenIDConnectProvider", "iam:TagOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider", "iam:AddClientIDToOpenIDConnectProvider",
      "iam:CreateServiceLinkedRole", "iam:ListInstanceProfilesForRole",
    ]
    resources = ["*"]
  }

  # PassRole only to the services that legitimately run our workloads.
  statement {
    sid       = "PassRoleToServices"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values = [
        "build.apprunner.amazonaws.com", "tasks.apprunner.amazonaws.com",
        "codebuild.amazonaws.com", "ec2.amazonaws.com", "scheduler.amazonaws.com",
      ]
    }
  }

  # Assume the cross-account dns-delegation role in the parent-zone account, to write this
  # client's NS records. Scoped to that role name in any account of the org.
  statement {
    sid       = "AssumeDnsDelegation"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::*:role/dns-delegation"]
  }
}

# --- Guardrails: DENY the dangerous surface and self-tampering ---
data "aws_iam_policy_document" "deny" {
  # No identity/account/billing manipulation, ever.
  statement {
    sid    = "DenySensitive"
    effect = "Deny"
    actions = [
      "iam:*User*", "iam:*Group*", "iam:*AccessKey*", "iam:*LoginProfile*",
      "iam:*SAMLProvider*", "iam:*MFADevice*", "iam:*ServiceSpecificCredential*",
      "organizations:*", "account:*", "billing:*", "budgets:*", "ce:*", "cur:*",
      "aws-portal:*",
    ]
    resources = ["*"]
  }

  # A compromised pipeline must not be able to widen its own privileges: deny any change to the
  # tfc-deploy role itself or to the app.terraform.io OIDC provider it trusts.
  statement {
    sid    = "ProtectSecurityPrimitives"
    effect = "Deny"
    actions = [
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:UpdateAssumeRolePolicy", "iam:DeleteRole", "iam:UpdateRole",
      "iam:DeleteOpenIDConnectProvider", "iam:AddClientIDToOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = [
      aws_iam_role.tfc_deploy.arn,
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/app.terraform.io",
    ]
  }
}

# --- Org-admin profile (management account only) ---
# Governs the Organization, Identity Center and billing. Broad by design, but still cannot mint
# static credentials or tamper with its own trust — those two denials hold for every profile.
data "aws_iam_policy_document" "org_admin_allow" {
  statement {
    sid    = "OrgGovernance"
    effect = "Allow"
    actions = [
      "organizations:*", "account:*",
      "sso:*", "sso-admin:*", "sso-directory:*", "identitystore:*",
      "iam:*",
      "ce:*", "cur:*", "budgets:*", "billing:*", "payments:*", "invoicing:*", "tax:*",
      "cloudtrail:*", "config:*", "guardduty:*",
      "s3:*", "ssm:*", "kms:*", "logs:*", "sts:*", "tag:*",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "org_admin_deny" {
  statement {
    sid       = "NoStaticCredentials"
    effect    = "Deny"
    actions   = ["iam:*User*", "iam:*AccessKey*", "iam:*LoginProfile*"]
    resources = ["*"]
  }
  statement {
    sid    = "ProtectSecurityPrimitives"
    effect = "Deny"
    actions = [
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:UpdateAssumeRolePolicy", "iam:DeleteRole", "iam:UpdateRole",
      "iam:DeleteOpenIDConnectProvider", "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = [
      aws_iam_role.tfc_deploy.arn,
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/app.terraform.io",
    ]
  }
}

locals {
  allow_json = var.profile == "org-admin" ? data.aws_iam_policy_document.org_admin_allow.json : data.aws_iam_policy_document.allow.json
  deny_json  = var.profile == "org-admin" ? data.aws_iam_policy_document.org_admin_deny.json : data.aws_iam_policy_document.deny.json
}

resource "aws_iam_role_policy" "allow" {
  name   = "${var.role_name}-allow"
  role   = aws_iam_role.tfc_deploy.id
  policy = local.allow_json
}

resource "aws_iam_role_policy" "deny" {
  name   = "${var.role_name}-guardrails"
  role   = aws_iam_role.tfc_deploy.id
  policy = local.deny_json
}
