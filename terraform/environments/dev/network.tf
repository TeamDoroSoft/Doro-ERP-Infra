resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = data.aws_subnet.public_a.id

  tags = {
    Name = "${local.name_prefix}-nat-a"
  }

  depends_on = [terraform_data.network_contract]
}

# The route already exists but points to a deleted NAT Gateway and is in
# blackhole state. The import block adopts only this route so Terraform can
# replace its target without importing the shared Route Table itself.
import {
  to = aws_route.private_app_default
  id = "rtb-087a7c346ff32a3ee_0.0.0.0/0"
}

resource "aws_route" "private_app_default" {
  route_table_id         = data.aws_route_table.private_app.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.team2.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [data.aws_route_table.private_app.id]

  tags = {
    Name = "${local.name_prefix}-s3"
  }
}

resource "aws_security_group" "aws_endpoints" {
  name        = "${local.name_prefix}-aws-endpoints"
  description = "HTTPS from the team2 VPC to private AWS service endpoints."
  vpc_id      = data.aws_vpc.team2.id

  tags = {
    Name = "${local.name_prefix}-aws-endpoints"
  }
}

resource "aws_vpc_security_group_ingress_rule" "aws_endpoints_https" {
  security_group_id = aws_security_group.aws_endpoints.id
  description       = "HTTPS from the team2 VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = data.aws_vpc.team2.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "aws_endpoints_all" {
  security_group_id = aws_security_group.aws_endpoints.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset([
    "ecr.api",
    "ecr.dkr",
    "logs",
    "secretsmanager",
    "sqs",
    "sts"
  ])

  vpc_id              = data.aws_vpc.team2.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [data.aws_subnet.app_a.id]
  security_group_ids  = [aws_security_group.aws_endpoints.id]

  tags = {
    Name = "${local.name_prefix}-${replace(each.value, ".", "-")}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "existing_ssm_from_vpc" {
  security_group_id = data.aws_security_group.existing_vpc_endpoints.id
  description       = "SSM HTTPS from the team2 VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = data.aws_vpc.team2.cidr_block
}
