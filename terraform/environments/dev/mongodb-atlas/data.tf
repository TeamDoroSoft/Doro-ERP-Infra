data "aws_caller_identity" "current" {}

data "aws_vpc" "team2" {
  id = local.network.vpc_id
}

data "aws_subnet" "data_a" {
  id = local.network.data_a_subnet_id
}

data "aws_subnet" "data_c" {
  id = local.network.data_c_subnet_id
}

data "aws_eks_cluster" "dev" {
  name = "doro-erp-dev"
}

data "aws_security_group" "management" {
  name   = "doro-erp-dev-management"
  vpc_id = data.aws_vpc.team2.id
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
      condition = alltrue([
        data.aws_subnet.data_a.vpc_id == data.aws_vpc.team2.id,
        data.aws_subnet.data_c.vpc_id == data.aws_vpc.team2.id
      ])
      error_message = "The configured data subnets no longer belong to the approved team2 VPC."
    }
  }
}
