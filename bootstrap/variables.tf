variable "aws_account_id" {
  description = "AWS account in which the Doro ERP prod infrastructure is created."
  type        = string
  default     = "727646470302"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "AWS region for the Doro ERP prod environment."
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
  default     = "doro-erp-prod-tfstate-727646470302-ap-northeast-2"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "state_bucket_name must be a valid lowercase S3 bucket name."
  }
}

variable "hosted_zone_name" {
  description = "Existing registered domain whose Route 53 public hosted zone is managed by Bootstrap."
  type        = string
  default     = "minseok.click"

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$", var.hosted_zone_name))
    error_message = "hosted_zone_name must be a valid registered DNS domain name."
  }
}

variable "github_oidc_provider_arn" {
  description = "Existing account-shared GitHub Actions OIDC provider ARN, read without Terraform ownership."
  type        = string
  default     = "arn:aws:iam::727646470302:oidc-provider/token.actions.githubusercontent.com"

  validation {
    condition = (
      var.github_oidc_provider_arn ==
      "arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
    )
    error_message = "github_oidc_provider_arn must reference the GitHub Actions OIDC provider in aws_account_id."
  }
}

variable "terraform_operator_user_names" {
  description = "Existing IAM users assigned exclusively to the Terraform operator group."
  type        = set(string)
  default = [
    "a-student-02",
    "a-student-06",
    "b-student-05",
    "b-student-11"
  ]

  validation {
    condition = length(var.terraform_operator_user_names) > 0 && alltrue([
      for name in var.terraform_operator_user_names :
      can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", name))
    ])
    error_message = "Every Terraform operator must be a valid existing IAM user name."
  }
}

variable "terraform_operator_additional_principal_arns" {
  description = "Optional non-user IAM principals also allowed to assume the Terraform execution role."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.terraform_operator_additional_principal_arns :
      can(regex("^arn:aws:iam::727646470302:role/[A-Za-z0-9+=,.@_/-]+$", arn))
    ])
    error_message = "Every additional Terraform operator must be an IAM role ARN in account 727646470302."
  }
}

variable "ssm_operator_group_name" {
  description = "Terraform-managed IAM group whose members may open audited Prod SSM sessions."
  type        = string
  default     = "team2-doro-load-group"
}

variable "ssm_operator_user_names" {
  description = "Existing IAM users assigned exclusively to the Terraform-managed Prod SSM operator group."
  type        = set(string)
  default = [
    "a-student-02",
    "a-student-06",
    "b-student-05",
    "b-student-11"
  ]

  validation {
    condition = length(var.ssm_operator_user_names) > 0 && alltrue([
      for name in var.ssm_operator_user_names :
      can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", name))
    ])
    error_message = "Every SSM operator must be a valid existing IAM user name."
  }
}
