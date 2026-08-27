variable "aws_account_id" {
  description = "AWS account that owns the Doro ERP Prod environment."
  type        = string
  default     = "727646470302"
}

variable "aws_region" {
  description = "AWS region for the Redis deployment."
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

variable "redis_user_id" {
  description = "Existing password-protected ElastiCache user ID whose user name is default. Create only the user outside Terraform so its password never enters Terraform state."
  type        = string

  validation {
    condition     = length(trimspace(var.redis_user_id)) > 0
    error_message = "redis_user_id must identify the pre-created password-protected Store Access user."
  }
}

variable "edge_rate_limit_redis_user_id" {
  description = "Existing password-protected ElastiCache user ID restricted to the Edge public-checkout rate-limit key prefix. Create only the user outside Terraform so its password never enters Terraform state."
  type        = string

  validation {
    condition     = length(trimspace(var.edge_rate_limit_redis_user_id)) > 0 && var.edge_rate_limit_redis_user_id != var.redis_user_id
    error_message = "edge_rate_limit_redis_user_id must identify a distinct pre-created Edge rate-limit user."
  }
}

variable "redis_node_type" {
  description = "ElastiCache node type for Prod Alpha."
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
