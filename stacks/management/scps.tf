# =============================================================================================
# Service Control Policies. Deny-based (compose with the default FullAWSAccess), always attached —
# the plan/apply is the review gate. SCPs never apply to the management account, so root
# break-glass there is preserved.
#
# Safety notes:
# - None of these deny actions that `tfc-deploy` performs, so deploys keep working.
# - `bootstrap` runs as OrganizationAccountAccessRole; nothing here blocks creating tfc-deploy.
# - Requires the SERVICE_CONTROL_POLICY type enabled in the organization (default for all-features
#   orgs; otherwise enable it in Organizations settings).
# =============================================================================================

# --- Baseline: org-wide protections (attached to Root; management account is exempt) ---
data "aws_iam_policy_document" "baseline" {
  statement {
    sid       = "DenyLeaveOrganization"
    effect    = "Deny"
    actions   = ["organizations:LeaveOrganization"]
    resources = ["*"]
  }
  statement {
    sid       = "DenyRootUser"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:root"]
    }
  }
  statement {
    sid    = "ProtectSecurityServices"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging", "cloudtrail:DeleteTrail",
      "config:DeleteConfigurationRecorder", "config:StopConfigurationRecorder", "config:DeleteDeliveryChannel",
      "guardduty:DeleteDetector", "guardduty:DisassociateFromMasterAccount",
    ]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "baseline" {
  name        = "baseline-guardrails"
  description = "Org-wide: no leaving the org, no root user, protect CloudTrail/Config/GuardDuty."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.baseline.json
}

resource "aws_organizations_policy_attachment" "baseline" {
  policy_id = aws_organizations_policy.baseline.id
  target_id = local.root_id
}

# --- Region lock: deny actions outside allowed_regions (global services exempt) ---
data "aws_iam_policy_document" "region_lock" {
  statement {
    sid    = "DenyOutsideAllowedRegions"
    effect = "Deny"
    not_actions = [
      "iam:*", "sts:*", "organizations:*", "account:*",
      "route53:*", "route53domains:*", "cloudfront:*", "globalaccelerator:*",
      "shield:*", "waf:*", "wafv2:*", "support:*", "trustedadvisor:*",
      "health:*", "budgets:*", "ce:*", "cur:*", "tag:*", "notifications:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }
}

resource "aws_organizations_policy" "region_lock" {
  name        = "region-lock"
  description = "Deny actions outside ${join(", ", var.allowed_regions)} (global services exempt)."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.region_lock.json
}

resource "aws_organizations_policy_attachment" "region_lock" {
  policy_id = aws_organizations_policy.region_lock.id
  target_id = aws_organizations_organizational_unit.foundational["Workloads"].id
}

# --- Prod: protect encryption / data at rest ---
data "aws_iam_policy_document" "prod" {
  statement {
    sid    = "ProtectEncryption"
    effect = "Deny"
    actions = [
      "kms:ScheduleKeyDeletion", "kms:DisableKey",
      "ec2:DisableEbsEncryptionByDefault",
      "s3:PutAccountPublicAccessBlock",
    ]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "prod" {
  name        = "prod-guardrails"
  description = "Prod: no deleting KMS keys, no disabling default EBS encryption, no account-level S3 public access."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.prod.json
}

resource "aws_organizations_policy_attachment" "prod" {
  policy_id = aws_organizations_policy.prod.id
  target_id = aws_organizations_organizational_unit.environment["prod"].id
}

# --- NonProd: block expensive / accelerated compute ---
data "aws_iam_policy_document" "nonprod" {
  statement {
    sid       = "DenyExpensiveInstanceFamilies"
    effect    = "Deny"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:*:*:instance/*"]
    condition {
      test     = "StringLike"
      variable = "ec2:InstanceType"
      values   = ["p*", "g*", "x*", "dl*", "trn*", "inf*", "*.metal", "*.24xlarge", "*.16xlarge", "*.12xlarge"]
    }
  }
}

resource "aws_organizations_policy" "nonprod" {
  name        = "nonprod-guardrails"
  description = "NonProd: block GPU/accelerated and very large EC2 instance types."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.nonprod.json
}

resource "aws_organizations_policy_attachment" "nonprod" {
  policy_id = aws_organizations_policy.nonprod.id
  target_id = aws_organizations_organizational_unit.environment["nonprod"].id
}

# --- Suspended: quarantine accounts being decommissioned (deny all but read/support/billing) ---
data "aws_iam_policy_document" "suspended" {
  statement {
    sid    = "Quarantine"
    effect = "Deny"
    not_actions = [
      "support:*", "health:*", "ce:*", "cur:*", "billing:*",
      "account:GetAccountInformation", "cloudtrail:LookupEvents",
      "iam:Get*", "iam:List*", "s3:Get*", "s3:List*",
    ]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "suspended" {
  name        = "suspended-quarantine"
  description = "Freeze accounts under Suspended: read/support/billing only."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.suspended.json
}

resource "aws_organizations_policy_attachment" "suspended" {
  policy_id = aws_organizations_policy.suspended.id
  target_id = aws_organizations_organizational_unit.foundational["Suspended"].id
}
