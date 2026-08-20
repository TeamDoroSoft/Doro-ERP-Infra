variable "aws_account_id" {
  description = "AWS account that owns the Doro ERP Dev environment."
  type        = string
  default     = "727646470302"
}

variable "aws_region" {
  description = "AWS region for regional Dev resources."
  type        = string
  default     = "ap-northeast-2"
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
  description = "IAM principal granted EKS cluster administrator access for Dev."
  type        = string
  default     = "arn:aws:iam::727646470302:user/a-student-06"
}

variable "domain_name" {
  description = "Public Dev Alpha hostname."
  type        = string
  default     = "doro.minseok.click"
}

variable "hosted_zone_name" {
  description = "Existing Route 53 public hosted zone."
  type        = string
  default     = "minseok.click"
}

variable "rds_backup_retention_days" {
  description = "RDS automated backup retention for Dev."
  type        = number
  default     = 7
}
