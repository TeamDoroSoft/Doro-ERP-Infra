output "state_bucket_name" {
  description = "S3 bucket that stores Terraform state."
  value       = aws_s3_bucket.terraform_state.id
}

output "route53_public_hosted_zone_id" {
  description = "Bootstrap-managed Route 53 public hosted zone ID."
  value       = aws_route53_zone.public.zone_id
}

output "route53_public_hosted_zone_name" {
  description = "Bootstrap-managed Route 53 public hosted zone name."
  value       = trimsuffix(aws_route53_zone.public.name, ".")
}

output "route53_public_hosted_zone_name_servers" {
  description = "Authoritative name servers that the domain registrar must delegate to."
  value       = aws_route53_zone.public.name_servers
}

output "terraform_execution_role_arn" {
  description = "Role assumed by approved Terraform operators."
  value       = aws_iam_role.terraform_execution.arn
}

output "terraform_operator_group_name" {
  description = "Terraform-managed IAM group allowed to assume the Prod Terraform execution role."
  value       = aws_iam_group.terraform_operators.name
}

output "terraform_operator_user_names" {
  description = "Existing IAM users managed as the exact membership of the Terraform operator group."
  value       = sort(tolist(var.terraform_operator_user_names))
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
  description = "Policy attached to the Terraform-managed team2 operator group for audited Prod SSM sessions."
  value       = aws_iam_policy.prod_ssm_access.arn
}

output "prod_ssm_operator_group_name" {
  description = "Terraform-managed IAM group allowed to open audited Prod SSM sessions."
  value       = aws_iam_group.team2_operators.name
}

output "prod_ssm_operator_user_names" {
  description = "Existing IAM users managed as the exact membership of the Prod SSM operator group."
  value       = sort(tolist(var.ssm_operator_user_names))
}

output "github_actions_oidc_provider_arn" {
  description = "Terraform-managed GitHub Actions OIDC provider ARN."
  value       = aws_iam_openid_connect_provider.github.arn
}
