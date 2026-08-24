output "state_bucket_name" {
  description = "S3 bucket that stores Terraform state."
  value       = aws_s3_bucket.terraform_state.id
}

output "terraform_execution_role_arn" {
  description = "Role assumed by approved Terraform operators."
  value       = aws_iam_role.terraform_execution.arn
}

output "doro_erp_service_ecr_publisher_role_arn" {
  description = "GitHub Actions role allowed to push Doro ERP service images to ECR."
  value       = aws_iam_role.doro_erp_service_ecr_publisher.arn
}

output "workload_permissions_boundary_arn" {
  description = "Permissions boundary required for Doro ERP workload roles."
  value       = aws_iam_policy.workload_boundary.arn
}

output "prod_ssm_access_policy_arn" {
  description = "Policy attached to the existing team2 operator group for audited Prod SSM sessions."
  value       = aws_iam_policy.prod_ssm_access.arn
}
