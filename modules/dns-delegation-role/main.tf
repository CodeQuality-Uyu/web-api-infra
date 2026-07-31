# Cross-account DNS delegation role, created in the account that OWNS the parent zone
# (e.g. ecolors.app). Any client foundation, running as `tfc-deploy` in its own account, assumes
# this role to UPSERT its own NS records into the parent zone — so onboarding a client delegates
# its subdomain automatically, with no manual step in the parent zone.

# Who may assume it: only `tfc-deploy` roles, and only from inside this AWS Organization.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.org_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/${var.consumer_role_name}"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = "Client foundations assume this to write NS delegation records into the parent zone."
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
  tags                 = var.tags
}

# What it can do: change ONLY NS records in ONLY the parent zone. Restricting the record type to
# NS prevents a client from hijacking the apex A record or any other record in the parent zone.
data "aws_iam_policy_document" "perms" {
  statement {
    sid       = "ChangeNsRecordsInParentZone"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.hosted_zone_id}"]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["NS"]
    }
  }
  statement {
    sid       = "ReadParentZone"
    effect    = "Allow"
    actions   = ["route53:ListResourceRecordSets", "route53:GetHostedZone"]
    resources = ["arn:aws:route53:::hostedzone/${var.hosted_zone_id}"]
  }
  statement {
    sid       = "TrackChange"
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.role_name}-ns-only"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.perms.json
}
