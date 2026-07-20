output "db_address" {
  value = aws_db_instance.this.address
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}

output "master_secret_arn" {
  value     = aws_secretsmanager_secret.master.arn
  sensitive = true
}

output "connection_string_arns" {
  description = "Map db_name -> SSM SecureString ARN (App Runner runtime secrets)."
  value       = { for k, p in aws_ssm_parameter.conn : k => p.arn }
}

output "connection_string_names" {
  description = "Map db_name -> SSM parameter name (migration job reads this at runtime)."
  value       = { for k, p in aws_ssm_parameter.conn : k => p.name }
}

output "connection_strings" {
  description = "Map db_name -> full connection string VALUE (host/user/pass). Sensitive. Consumed cross-account via remote state, then re-stored in the consumer's own SSM."
  value       = { for k in var.db_names : k => "${local.conn_base};Database=${k}" }
  sensitive   = true
}

output "connection_string_kms_key_arn" {
  description = "KMS key used by SSM SecureString (default aws/ssm alias)."
  value       = "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"
}
