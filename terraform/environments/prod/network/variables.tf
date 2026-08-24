variable "aws_account_id" {
  description = "AWS account that owns the Doro ERP Prod network."
  type        = string
  default     = "727646470302"
}

variable "aws_region" {
  description = "AWS region for the Prod network."
  type        = string
  default     = "ap-northeast-2"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR assigned to the Terraform-managed Prod VPC."
  type        = string
  default     = "10.24.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR."
  }
}

variable "availability_zones" {
  description = "Two availability zones used by EKS, ALB, RDS, and Redis."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]

  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "Exactly two distinct availability zones are required."
  }
}

variable "subnet_cidrs" {
  description = "CIDRs for the public, private application, and private data subnets."
  type = object({
    public_a = string
    public_c = string
    app_a    = string
    app_c    = string
    data_a   = string
    data_c   = string
  })
  default = {
    public_a = "10.24.0.0/24"
    public_c = "10.24.1.0/24"
    app_a    = "10.24.10.0/24"
    app_c    = "10.24.11.0/24"
    data_a   = "10.24.20.0/24"
    data_c   = "10.24.21.0/24"
  }

  validation {
    condition = alltrue([
      for cidr in values(var.subnet_cidrs) : can(cidrnetmask(cidr))
    ]) && length(distinct(values(var.subnet_cidrs))) == 6
    error_message = "All six subnet CIDRs must be valid and distinct."
  }
}
