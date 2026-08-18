variable "aws_account_id" {
  description = "AWS account that owns the Doro ERP Dev environment."
  type        = string
  default     = "727646470302"
}

variable "aws_region" {
  description = "AWS region containing the Doro ERP VPC."
  type        = string
  default     = "ap-northeast-2"
}

variable "atlas_org_id" {
  description = "MongoDB Atlas organization ID. This identifier is not a credential."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{24}$", var.atlas_org_id))
    error_message = "atlas_org_id must be a 24-character Atlas organization ID."
  }
}

variable "atlas_project_name" {
  description = "MongoDB Atlas project created for Dev Alpha."
  type        = string
  default     = "doro-erp-dev-alpha"
}

variable "atlas_cluster_name" {
  description = "MongoDB Atlas cluster name."
  type        = string
  default     = "doro-erp-dev-alpha-audit"
}

variable "atlas_instance_size" {
  description = "Dedicated Atlas tier. M10 is the minimum tier used with AWS PrivateLink."
  type        = string
  default     = "M10"

  validation {
    condition     = can(regex("^M([1-9][0-9]|[1-9][0-9]{2,})$", var.atlas_instance_size))
    error_message = "Use a dedicated Atlas M-tier such as M10."
  }
}

variable "atlas_termination_protection_enabled" {
  description = "Protect the Atlas cluster from deletion. Set false and apply before an intentional destroy."
  type        = bool
  default     = true
}
