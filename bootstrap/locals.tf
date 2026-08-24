locals {
  common_tags = {
    Project     = "Doro-ERP"
    Environment = "prod"
    Cell        = "alpha"
    Team        = "team2"
    ManagedBy   = "terraform"
  }

  terraform_role_name                  = "doro-erp-prod-terraform"
  workload_boundary_name               = "doro-erp-guardrail-prod"
  project_role_arn_pattern             = "arn:aws:iam::${var.aws_account_id}:role/doro-erp-prod-*"
  project_policy_arn_pattern           = "arn:aws:iam::${var.aws_account_id}:policy/doro-erp-prod-*"
  project_instance_profile_arn_pattern = "arn:aws:iam::${var.aws_account_id}:instance-profile/doro-erp-prod-*"
  workload_boundary_arn                = "arn:aws:iam::${var.aws_account_id}:policy/${local.workload_boundary_name}"

  prod_ssm_access_policy_arn = "arn:aws:iam::${var.aws_account_id}:policy/doro-erp-prod-ssm-access"

  # Canonical GitHub Actions ECR push role. See
  # bootstrap/doro-erp-service-ecr-publisher.tf.
  doro_erp_service_ecr_publisher_role_arn = "arn:aws:iam::${var.aws_account_id}:role/doro-erp-service-ecr-publisher"
  doro_erp_service_ecr_publish_policy_arn = "arn:aws:iam::${var.aws_account_id}:policy/DoroErpServiceEcrPublishPolicy"
}
