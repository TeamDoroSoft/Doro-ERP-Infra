locals {
  name_prefix = "doro-erp-prod"

  common_tags = {
    Project     = "Doro-ERP"
    Environment = "prod"
    Cell        = "alpha"
    Team        = "team2"
    ManagedBy   = "terraform"
  }

  subnets = {
    public_a = {
      cidr = var.subnet_cidrs.public_a
      az   = var.availability_zones[0]
      tier = "public"
    }
    public_c = {
      cidr = var.subnet_cidrs.public_c
      az   = var.availability_zones[1]
      tier = "public"
    }
    app_a = {
      cidr = var.subnet_cidrs.app_a
      az   = var.availability_zones[0]
      tier = "app"
    }
    app_c = {
      cidr = var.subnet_cidrs.app_c
      az   = var.availability_zones[1]
      tier = "app"
    }
    data_a = {
      cidr = var.subnet_cidrs.data_a
      az   = var.availability_zones[0]
      tier = "data"
    }
    data_c = {
      cidr = var.subnet_cidrs.data_c
      az   = var.availability_zones[1]
      tier = "data"
    }
  }

  interface_endpoint_services = toset([
    "ec2messages",
    "ecr.api",
    "ecr.dkr",
    "logs",
    "secretsmanager",
    "sqs",
    "ssm",
    "ssmmessages",
    "sts"
  ])

  default_vpc_resource_tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-default"
  })
}
