resource "aws_security_group" "management" {
  name        = "${local.name_prefix}-management"
  description = "SSM-only management instance with no inbound rules."
  vpc_id      = data.aws_vpc.team2.id

  tags = {
    Name = "${local.name_prefix}-management"
  }
}

resource "aws_vpc_security_group_egress_rule" "management_https" {
  security_group_id = aws_security_group.management.id
  description       = "HTTPS to AWS APIs, EKS, package repositories, and external providers."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "management_mongodb" {
  security_group_id = aws_security_group.management.id
  description       = "TLS connection to the MongoDB Atlas public SRV targets."
  ip_protocol       = "tcp"
  from_port         = 27017
  to_port           = 27017
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "management_postgres" {
  security_group_id = aws_security_group.management.id
  description       = "PostgreSQL administration inside the Prod VPC."
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = data.aws_vpc.team2.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "management_redis" {
  security_group_id = aws_security_group.management.id
  description       = "TLS Redis verification inside the Prod VPC."
  ip_protocol       = "tcp"
  from_port         = 6379
  to_port           = 6379
  cidr_ipv4         = data.aws_vpc.team2.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "management_dns_udp" {
  security_group_id = aws_security_group.management.id
  description       = "DNS through the VPC resolver."
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = data.aws_vpc.team2.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "management_dns_tcp" {
  security_group_id = aws_security_group.management.id
  description       = "TCP DNS fallback through the VPC resolver."
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = data.aws_vpc.team2.cidr_block
}

resource "aws_instance" "management" {
  ami                         = data.aws_ssm_parameter.amazon_linux_2023_arm64.value
  instance_type               = "t4g.micro"
  subnet_id                   = data.aws_subnet.app_a.id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.management.name
  vpc_security_group_ids      = [aws_security_group.management.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    encrypted   = true
    volume_size = 10
    volume_type = "gp3"
  }

  user_data = <<-EOT
    #!/bin/bash
    dnf install -y postgresql15 jq
  EOT

  tags = {
    Name = "${local.name_prefix}-management"
  }

  depends_on = [
    terraform_data.network_contract,
    aws_ssm_document.management_session,
    aws_iam_role_policy.session_logs["management"]
  ]
}
