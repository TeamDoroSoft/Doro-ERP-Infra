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

data "aws_subnet" "data_a" {
  id = local.network.subnet_ids.data_a
}

data "aws_subnet" "data_c" {
  id = local.network.subnet_ids.data_c
}

data "aws_eks_cluster" "prod" {
  name = "doro-erp-prod"
}

data "aws_security_group" "management" {
  name   = "doro-erp-prod-management"
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
      error_message = "The Terraform-managed Prod VPC CIDR no longer matches the network state output."
    }

    precondition {
      condition = alltrue([
        data.aws_subnet.data_a.vpc_id == data.aws_vpc.team2.id,
        data.aws_subnet.data_c.vpc_id == data.aws_vpc.team2.id,
        contains(data.aws_eks_cluster.prod.vpc_config[0].subnet_ids, local.network.subnet_ids.app_a),
        contains(data.aws_eks_cluster.prod.vpc_config[0].subnet_ids, local.network.subnet_ids.app_c)
      ])
      error_message = "The configured VPC, data subnets, or EKS cluster no longer match the Prod network contract."
    }
  }
}
