output "role_arn" {
  description = "ARN of the delegation role. Set this as dns_delegation_role_arn in the factory."
  value       = aws_iam_role.this.arn
}
