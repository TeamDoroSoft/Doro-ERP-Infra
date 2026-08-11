output "state_bucket_name" {
  description = "S3 bucket that stores Terraform state."
  value       = aws_s3_bucket.terraform_state.id
}

output "terraform_execution_role_arn" {
  description = "Role assumed by approved Terraform operators."
  value       = aws_iam_role.terraform_execution.arn
}

output "github_ecr_push_role_arn" {
  description = "GitHub Actions role allowed to push Doro ERP images."
  value       = aws_iam_role.github_ecr_push.arn
}

output "workload_permissions_boundary_arn" {
  description = "Permissions boundary required for Doro ERP workload roles."
  value       = aws_iam_policy.workload_boundary.arn
}
