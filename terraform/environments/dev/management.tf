resource "aws_security_group" "management" {
  name        = "${local.name_prefix}-management"
  description = "SSM-only management instance with no inbound rules."
  vpc_id      = data.aws_vpc.team2.id

  tags = {
    Name = "${local.name_prefix}-management"
  }
}

resource "aws_vpc_security_group_egress_rule" "management_all" {
  security_group_id = aws_security_group.management.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
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
    aws_route.private_app_default,
    aws_vpc_security_group_ingress_rule.existing_ssm_from_vpc
  ]
}
