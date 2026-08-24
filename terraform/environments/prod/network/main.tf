data "aws_caller_identity" "current" {}

resource "terraform_data" "account_guard" {
  input = data.aws_caller_identity.current.account_id

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "Refusing to manage a VPC outside the expected AWS account."
    }
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.name_prefix
  }

  depends_on = [terraform_data.account_guard]
}

# AWS creates the default Security Group as a side effect. Adopt it with no
# ingress or egress rules so an accidental attachment does not grant traffic.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-default"
  }
}

# The default Route Table and Network ACL remain unused/default-behavior
# resources. Tag them explicitly without taking over routes or ACL rules.
resource "aws_ec2_tag" "default_route_table" {
  for_each = local.default_vpc_resource_tags

  resource_id = aws_vpc.this.default_route_table_id
  key         = each.key
  value       = each.value
}

resource "aws_ec2_tag" "default_network_acl" {
  for_each = local.default_vpc_resource_tags

  resource_id = aws_vpc.this.default_network_acl_id
  key         = each.key
  value       = each.value
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(
    {
      Name        = "${local.name_prefix}-${replace(each.key, "_", "-")}"
      NetworkTier = each.value.tier
    },
    each.value.tier == "public" ? {
      "kubernetes.io/role/elb" = "1"
    } : {},
    each.value.tier == "app" ? {
      "kubernetes.io/role/internal-elb" = "1"
    } : {}
  )
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${local.name_prefix}-public"
    NetworkTier = "public"
  }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = toset(["public_a", "public_c"])

  subnet_id      = aws_subnet.this[each.value].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.this["public_a"].id

  tags = {
    Name = "${local.name_prefix}-nat-a"
  }

  depends_on = [aws_route.public_default]
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${local.name_prefix}-private-app"
    NetworkTier = "app"
  }
}

resource "aws_route" "app_default" {
  route_table_id         = aws_route_table.app.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "app" {
  for_each = toset(["app_a", "app_c"])

  subnet_id      = aws_subnet.this[each.value].id
  route_table_id = aws_route_table.app.id
}

resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${local.name_prefix}-private-data"
    NetworkTier = "data"
  }
}

resource "aws_route_table_association" "data" {
  for_each = toset(["data_a", "data_c"])

  subnet_id      = aws_subnet.this[each.value].id
  route_table_id = aws_route_table.data.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.app.id, aws_route_table.data.id]

  tags = {
    Name = "${local.name_prefix}-s3"
  }
}

resource "aws_security_group" "interface_endpoints" {
  name        = "${local.name_prefix}-interface-endpoints"
  description = "HTTPS from the Prod VPC to private AWS service endpoints."
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-interface-endpoints"
  }
}

resource "aws_vpc_security_group_ingress_rule" "interface_endpoints_https" {
  security_group_id = aws_security_group.interface_endpoints.id
  description       = "HTTPS from the Prod VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = aws_vpc.this.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "interface_endpoints_all" {
  security_group_id = aws_security_group.interface_endpoints.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# A single endpoint ENI in App A keeps the Prod cost down. App C reaches it
# over the VPC-local route; production should place endpoint ENIs in each AZ.
resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoint_services

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.this["app_a"].id]
  security_group_ids  = [aws_security_group.interface_endpoints.id]

  tags = {
    Name = "${local.name_prefix}-${replace(each.value, ".", "-")}"
  }
}
