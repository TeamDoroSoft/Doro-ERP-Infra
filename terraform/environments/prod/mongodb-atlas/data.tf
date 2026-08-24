data "aws_caller_identity" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.network_state_bucket
    key    = var.network_state_key
    region = var.aws_region
  }
}

data "aws_vpc" "team2" {
  id = local.network.vpc_id
}

resource "terraform_data" "network_contract" {
  input = data.aws_vpc.team2.id

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "Refusing to manage resources outside the expected AWS account."
    }

    precondition {
      condition     = data.aws_vpc.team2.cidr_block == local.network.vpc_cidr
      error_message = "The Terraform-managed Prod VPC CIDR no longer matches the network state output."
    }

    precondition {
      condition     = local.network.nat_gateway_id != "" && local.network.nat_public_ip != ""
      error_message = "The doro-erp-prod-nat-a NAT Gateway must be available in the approved team2 VPC with a public IP."
    }
  }
}
