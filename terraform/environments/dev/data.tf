data "aws_caller_identity" "current" {}

data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

data "aws_vpc" "team2" {
  id = local.existing_network.vpc_id
}

data "aws_subnet" "public_a" {
  id = local.existing_network.public_a_subnet_id
}

data "aws_subnet" "public_c" {
  id = local.existing_network.public_c_subnet_id
}

data "aws_subnet" "app_a" {
  id = local.existing_network.app_a_subnet_id
}

data "aws_subnet" "app_c" {
  id = local.existing_network.app_c_subnet_id
}

data "aws_subnet" "data_a" {
  id = local.existing_network.data_a_subnet_id
}

data "aws_subnet" "data_c" {
  id = local.existing_network.data_c_subnet_id
}

data "aws_route_table" "private_app" {
  route_table_id = local.existing_network.private_app_route_id
}

data "aws_route_table" "private_data" {
  route_table_id = local.existing_network.private_data_route_id
}

data "aws_security_group" "existing_vpc_endpoints" {
  name   = local.existing_network.vpc_endpoint_sg_name
  vpc_id = data.aws_vpc.team2.id
}

data "aws_route53_zone" "public" {
  name         = "${var.hosted_zone_name}."
  private_zone = false
}

data "aws_lb" "alpha" {
  name = "${local.name_prefix}-alpha"
}

data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_ssm_parameter" "amazon_linux_2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "terraform_data" "network_contract" {
  input = data.aws_vpc.team2.id

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "Refusing to manage resources outside the expected AWS account."
    }

    precondition {
      condition     = data.aws_vpc.team2.cidr_block == local.existing_network.vpc_cidr
      error_message = "The existing team2 VPC CIDR no longer matches the approved network contract."
    }

    precondition {
      condition = alltrue([
        data.aws_subnet.public_a.vpc_id == data.aws_vpc.team2.id,
        data.aws_subnet.public_c.vpc_id == data.aws_vpc.team2.id,
        data.aws_subnet.app_a.vpc_id == data.aws_vpc.team2.id,
        data.aws_subnet.app_c.vpc_id == data.aws_vpc.team2.id,
        data.aws_subnet.data_a.vpc_id == data.aws_vpc.team2.id,
        data.aws_subnet.data_c.vpc_id == data.aws_vpc.team2.id
      ])
      error_message = "At least one configured subnet is no longer part of the team2 VPC."
    }
  }
}
