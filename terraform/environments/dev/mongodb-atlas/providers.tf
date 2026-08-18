provider "aws" {
  region = var.aws_region

  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.common_tags
  }
}

# Authentication is read from MONGODB_ATLAS_PUBLIC_KEY and
# MONGODB_ATLAS_PRIVATE_KEY. Never put either value in tfvars.
provider "mongodbatlas" {}
