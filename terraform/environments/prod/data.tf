data "aws_caller_identity" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.network_state_bucket
    key    = var.network_state_key
    region = var.aws_region
  }
}

data "terraform_remote_state" "bootstrap" {
  backend = "s3"

  config = {
    bucket = var.bootstrap_state_bucket
    key    = var.bootstrap_state_key
    region = var.aws_region
  }
}

data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

data "aws_eks_addon_version" "metrics_server" {
  addon_name         = "metrics-server"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

data "aws_eks_addon_version" "cloudwatch_observability" {
  addon_name         = "amazon-cloudwatch-observability"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

data "aws_vpc" "team2" {
  id = local.network.vpc_id
}

data "aws_subnet" "public_a" {
  id = local.network.subnet_ids.public_a
}

data "aws_subnet" "public_c" {
  id = local.network.subnet_ids.public_c
}

data "aws_subnet" "app_a" {
  id = local.network.subnet_ids.app_a
}

data "aws_subnet" "app_c" {
  id = local.network.subnet_ids.app_c
}

data "aws_subnet" "data_a" {
  id = local.network.subnet_ids.data_a
}

data "aws_subnet" "data_c" {
  id = local.network.subnet_ids.data_c
}

data "aws_route_table" "private_app" {
  route_table_id = local.network.route_table_ids.app
}

data "aws_route_table" "private_data" {
  route_table_id = local.network.route_table_ids.data
}

data "aws_lb" "gateway" {
  count = var.enable_gateway_backend ? 1 : 0

  name = "${local.name_prefix}-alpha-gateway"
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
      condition     = data.aws_vpc.team2.cidr_block == local.network.vpc_cidr
      error_message = "The Terraform-managed Prod VPC CIDR no longer matches the network state output."
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

resource "terraform_data" "bootstrap_contract" {
  input = data.terraform_remote_state.bootstrap.outputs.route53_public_hosted_zone_id

  lifecycle {
    precondition {
      condition = (
        data.terraform_remote_state.bootstrap.outputs.route53_public_hosted_zone_name ==
        var.hosted_zone_name
      )
      error_message = "The Bootstrap-managed public hosted zone does not match hosted_zone_name."
    }
  }
}
