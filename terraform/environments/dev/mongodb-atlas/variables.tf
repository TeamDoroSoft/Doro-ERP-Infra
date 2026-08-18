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

variable "atlas_region" {
  description = "Atlas AWS region that supports M0 Free clusters."
  type        = string
  default     = "AP_NORTHEAST_2"

  validation {
    condition     = can(regex("^[A-Z]+(_[A-Z0-9]+)+$", var.atlas_region))
    error_message = "atlas_region must use an Atlas region code such as AP_NORTHEAST_2."
  }
}
