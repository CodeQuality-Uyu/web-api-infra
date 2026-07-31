output "role_arn" {
  description = "ARN GitHub Actions uses as role-to-assume."
  value       = aws_iam_role.this.arn
}
