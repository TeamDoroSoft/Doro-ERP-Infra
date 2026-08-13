variable "aws_account_id" {
  description = "AWS account in which the Doro ERP dev infrastructure is created."
  type        = string
  default     = "727646470302"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "AWS region for the Doro ERP dev environment."
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_profile" {
  description = "Optional local AWS CLI profile. Leave null in AWS CloudShell."
  type        = string
  default     = null
  nullable    = true
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket for Terraform state."
  type        = string
  default     = "doro-erp-dev-tfstate-727646470302-ap-northeast-2"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "state_bucket_name must be a valid lowercase S3 bucket name."
  }
}

variable "terraform_operator_principal_arns" {
  description = "IAM principals allowed to assume the Terraform execution role."
  type        = set(string)
  default = [
    "arn:aws:iam::727646470302:user/a-student-06",
    "arn:aws:iam::727646470302:user/b-student-05"
  ]

  validation {
    condition = length(var.terraform_operator_principal_arns) > 0 && alltrue([
      for arn in var.terraform_operator_principal_arns :
      can(regex("^arn:aws:iam::727646470302:(user|role)/[A-Za-z0-9+=,.@_/-]+$", arn))
    ])
    error_message = "Every Terraform operator must be an IAM user or role ARN in account 727646470302."
  }
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub Actions OIDC provider in the shared AWS account."
  type        = string
  default     = "arn:aws:iam::727646470302:oidc-provider/token.actions.githubusercontent.com"
}

variable "github_ecr_subjects" {
  description = "GitHub OIDC subject claims allowed to push backend images to ECR."
  type        = set(string)
  default = [
    "repo:TeamDoroSoft/Doro-ERP-Service:ref:refs/heads/main",
    "repo:TeamDoroSoft/Doro-ERP-Service:environment:dev"
  ]

  validation {
    condition = length(var.github_ecr_subjects) > 0 && alltrue([
      for subject in var.github_ecr_subjects :
      startswith(subject, "repo:TeamDoroSoft/Doro-ERP-Service:")
    ])
    error_message = "GitHub subjects must be restricted to TeamDoroSoft/Doro-ERP-Service."
  }
}
