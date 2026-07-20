output "codebuild_project_name" {
  value = aws_codebuild_project.this.name
}

output "ci_role_arn" {
  description = "Role the app's GitHub Action assumes to run migrations."
  value       = aws_iam_role.ci.arn
}
