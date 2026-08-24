variable "aws_account_id" {
  description = "AWS account that owns the Doro ERP Prod environment."
  type        = string
  default     = "727646470302"
}

variable "aws_region" {
  description = "AWS region for regional Prod resources."
  type        = string
  default     = "ap-northeast-2"
}

variable "network_state_bucket" {
  description = "Existing S3 backend bucket containing the Terraform-managed Prod network state."
  type        = string
  default     = "doro-erp-prod-tfstate-727646470302-ap-northeast-2"
}

variable "network_state_key" {
  description = "S3 key of the Terraform-managed Prod network state."
  type        = string
  default     = "environments/prod/network/terraform.tfstate"
}

variable "eks_public_access_cidrs" {
  description = "Fixed public /32 CIDRs allowed to reach the EKS API. Set this in terraform.tfvars before plan."
  type        = list(string)

  validation {
    condition = length(var.eks_public_access_cidrs) > 0 && alltrue([
      for cidr in var.eks_public_access_cidrs : cidr != "0.0.0.0/0" && can(cidrnetmask(cidr))
    ])
    error_message = "Provide at least one restricted CIDR; 0.0.0.0/0 is not allowed."
  }
}

variable "eks_admin_principal_arn" {
  description = "IAM principal granted EKS cluster administrator access for Prod."
  type        = string
  default     = "arn:aws:iam::727646470302:user/a-student-06"
}

variable "domain_name" {
  description = "Public Prod Alpha hostname."
  type        = string
  default     = "doro.minseok.click"
}

variable "alb_origin_domain_name" {
  description = "Dedicated DNS hostname on the Regional ACM certificate used by CloudFront for the internal ALB VPC origin."
  type        = string
  default     = "origin.doro.minseok.click"

  validation {
    condition     = var.alb_origin_domain_name != var.domain_name && endswith(var.alb_origin_domain_name, ".${var.hosted_zone_name}")
    error_message = "alb_origin_domain_name must be a dedicated hostname beneath hosted_zone_name and must differ from domain_name."
  }
}

variable "hosted_zone_name" {
  description = "Existing Route 53 public hosted zone."
  type        = string
  default     = "minseok.click"
}

variable "enable_gateway_backend" {
  description = "Explicitly enable the CloudFront VPC origin, origin DNS, and ALB alarms only after the Gateway API ALB exists."
  type        = bool
}

variable "rds_backup_retention_days" {
  description = "RDS automated backup retention for Prod."
  type        = number
  default     = 7
}

variable "cloudwatch_log_retention_days" {
  description = "Retention in days for Prod Alpha Container Insights log groups."
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545,
      731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "cloudwatch_log_retention_days must be a retention value supported by CloudWatch Logs."
  }
}

variable "operations_alarm_email" {
  description = "Optional email address subscribed to Prod Alpha operational alarms. Confirmation is required after apply."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.operations_alarm_email == null || can(regex(
      "^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$",
      var.operations_alarm_email
    ))
    error_message = "operations_alarm_email must be null or a valid email address."
  }
}

variable "alb_target_5xx_alarm_threshold" {
  description = "Number of Edge target 5xx responses in five minutes that raises the Prod Alpha alarm."
  type        = number
  default     = 5

  validation {
    condition     = var.alb_target_5xx_alarm_threshold >= 1
    error_message = "alb_target_5xx_alarm_threshold must be at least 1."
  }
}
