locals {
  common_tags = {
    Project     = "Doro-ERP"
    Environment = "dev"
    Cell        = "alpha"
    Team        = "team2"
    ManagedBy   = "terraform"
  }

  terraform_role_name        = "doro-erp-dev-terraform"
  github_ecr_role_name       = "doro-erp-dev-github-ecr-push"
  workload_boundary_name     = "doro-erp-guardrail-dev"
  project_role_arn_pattern   = "arn:aws:iam::${var.aws_account_id}:role/doro-erp-dev-*"
  project_policy_arn_pattern = "arn:aws:iam::${var.aws_account_id}:policy/doro-erp-dev-*"
  workload_boundary_arn      = "arn:aws:iam::${var.aws_account_id}:policy/${local.workload_boundary_name}"
}
