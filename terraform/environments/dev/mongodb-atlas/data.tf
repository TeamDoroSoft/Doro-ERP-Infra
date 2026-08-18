data "aws_caller_identity" "current" {}

data "aws_vpc" "team2" {
  id = local.network.vpc_id
}

data "aws_nat_gateway" "dev" {
  vpc_id = data.aws_vpc.team2.id
  state  = "available"

  filter {
    name   = "tag:Name"
    values = ["doro-erp-dev-nat-a"]
  }
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
      error_message = "The existing team2 VPC CIDR no longer matches the approved network contract."
    }

    precondition {
      condition     = data.aws_nat_gateway.dev.vpc_id == data.aws_vpc.team2.id && data.aws_nat_gateway.dev.public_ip != ""
      error_message = "The doro-erp-dev-nat-a NAT Gateway must be available in the approved team2 VPC with a public IP."
    }
  }
}
