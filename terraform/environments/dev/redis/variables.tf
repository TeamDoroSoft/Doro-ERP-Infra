variable "aws_account_id" {
  description = "AWS account that owns the Doro ERP Dev environment."
  type        = string
  default     = "727646470302"
}

variable "aws_region" {
  description = "AWS region for the Redis deployment."
  type        = string
  default     = "ap-northeast-2"
}

variable "redis_user_id" {
  description = "Existing password-protected ElastiCache user ID whose user name is default. Create only the user outside Terraform so its password never enters Terraform state."
  type        = string

  validation {
    condition     = length(trimspace(var.redis_user_id)) > 0
    error_message = "redis_user_id must identify the pre-created password-protected Store Access user."
  }
}

variable "redis_node_type" {
  description = "ElastiCache node type for Dev Alpha."
  type        = string
  default     = "cache.t4g.micro"
}

variable "snapshot_retention_limit" {
  description = "Number of days to retain automatic Redis snapshots."
  type        = number
  default     = 1

  validation {
    condition     = var.snapshot_retention_limit >= 0 && var.snapshot_retention_limit <= 35
    error_message = "snapshot_retention_limit must be between 0 and 35."
  }
}
