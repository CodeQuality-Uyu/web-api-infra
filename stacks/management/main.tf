# Governance for the management (root) account. Today: IAM Identity Center permission sets +
# assignments (the billing role you need). The Organization, OUs and accounts already exist and
# are NOT recreated here. SCPs can be added later (see docs/arquitectura/03-identidad-y-gobierno).

data "aws_ssoadmin_instances" "this" {}

locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  # (permission set, managed policy) pairs
  ps_policies = merge([
    for name, a in var.access : {
      for p in a.managed_policies : "${name}|${p}" => { ps = name, policy = p }
    }
  ]...)

  # (permission set, group) pairs
  ps_groups = merge([
    for name, a in var.access : {
      for g in a.groups : "${name}|${g}" => { ps = name, group = g }
    }
  ]...)

  all_groups = toset(distinct(flatten([for name, a in var.access : a.groups])))
}

# Resolve each Identity Center group by its display name (groups must already exist).
data "aws_identitystore_group" "this" {
  for_each          = local.all_groups
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.value
    }
  }
}

resource "aws_ssoadmin_permission_set" "this" {
  for_each = var.access

  name             = each.key
  description      = each.value.description
  instance_arn     = local.instance_arn
  session_duration = "PT${each.value.session_hours}H"
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = local.ps_policies

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.ps].arn
  managed_policy_arn = each.value.policy
}

# Assign each permission set to its group(s) ON THE MANAGEMENT ACCOUNT — that's where
# consolidated billing for the whole organization is visible.
resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.ps_groups

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.ps].arn
  principal_id       = data.aws_identitystore_group.this[each.value.group].group_id
  principal_type     = "GROUP"
  target_id          = var.management_account_id
  target_type        = "AWS_ACCOUNT"
}
