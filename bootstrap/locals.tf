locals {
  common_tags = {
    Project     = "Doro-ERP"
    Environment = "dev"
    Cell        = "alpha"
    Team        = "team2"
    ManagedBy   = "terraform"
  }

  terraform_role_name                  = "doro-erp-dev-terraform"
  github_ecr_role_name                 = "doro-erp-dev-github-ecr-push"
  workload_boundary_name               = "doro-erp-guardrail-dev"
  project_role_arn_pattern             = "arn:aws:iam::${var.aws_account_id}:role/doro-erp-dev-*"
  project_policy_arn_pattern           = "arn:aws:iam::${var.aws_account_id}:policy/doro-erp-dev-*"
  project_instance_profile_arn_pattern = "arn:aws:iam::${var.aws_account_id}:instance-profile/doro-erp-dev-*"
  workload_boundary_arn                = "arn:aws:iam::${var.aws_account_id}:policy/${local.workload_boundary_name}"

  team2_doroload_ssm_access_policy_arn = "arn:aws:iam::${var.aws_account_id}:policy/team2-doroload-ssm-access-policy"

  # Known duplicate of doro-erp-dev-github-ecr-push, imported as-is pending
  # consolidation. See bootstrap/doro-erp-service-ecr-publisher.tf.
  doro_erp_service_ecr_publisher_role_arn = "arn:aws:iam::${var.aws_account_id}:role/doro-erp-service-ecr-publisher"
  doro_erp_service_ecr_publish_policy_arn = "arn:aws:iam::${var.aws_account_id}:policy/DoroErpServiceEcrPublishPolicy"
}
