output "permission_sets" {
  description = "Provisioned permission sets and their ARNs."
  value       = { for k, ps in aws_ssoadmin_permission_set.this : k => ps.arn }
}

output "identity_store_id" {
  value = local.identity_store_id
}

output "vended_account_ids" {
  description = "Map \"client-env\" -> new account id. The factory reads this (management_workspace)."
  value       = { for k, a in aws_organizations_account.this : k => a.id }
}

output "platform_account_ids" {
  description = "Map platform account name -> id (infrastructure, finops, ...)."
  value       = { for k, a in aws_organizations_account.platform : k => a.id }
}


