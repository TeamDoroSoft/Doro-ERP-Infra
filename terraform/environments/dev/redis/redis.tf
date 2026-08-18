resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.name_prefix}-redis"
  subnet_ids = [data.aws_subnet.data_a.id, data.aws_subnet.data_c.id]

  tags = {
    Name = "${local.name_prefix}-redis"
  }
}

resource "aws_elasticache_parameter_group" "this" {
  name   = "${local.name_prefix}-redis7"
  family = "redis7"

  parameter {
    name  = "notify-keyspace-events"
    value = "Egx"
  }

  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }

  tags = {
    Name = "${local.name_prefix}-redis7"
  }
}

resource "aws_elasticache_user_group" "this" {
  engine        = "redis"
  user_group_id = "doro-erp-dev-alpha-store-access"
  user_ids      = [var.redis_user_id]

  tags = {
    Name    = "${local.name_prefix}-store-access"
    Service = "store-access"
  }
}

resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis"
  description = "Redis TLS access from Doro ERP EKS and the SSM management instance."
  vpc_id      = data.aws_vpc.team2.id

  tags = {
    Name = "${local.name_prefix}-redis"
  }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_eks" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Redis TLS from the Dev EKS cluster"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = data.aws_eks_cluster.dev.vpc_config[0].cluster_security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_management" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Redis TLS from the SSM management instance"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = data.aws_security_group.management.id
}

resource "aws_vpc_security_group_egress_rule" "redis_all" {
  security_group_id = aws_security_group.redis.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${local.name_prefix}-session"
  description          = "Doro ERP Dev Alpha Store Access sessions and login rate limits"

  engine         = "redis"
  engine_version = "7.1"
  node_type      = var.redis_node_type
  port           = 6379

  num_cache_clusters         = 1
  automatic_failover_enabled = false
  multi_az_enabled           = false
  apply_immediately          = true

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  user_group_ids             = [aws_elasticache_user_group.this.user_group_id]

  parameter_group_name = aws_elasticache_parameter_group.this.name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.redis.id]

  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = "18:00-19:00"
  maintenance_window       = "sun:19:00-sun:20:00"

  tags = {
    Name    = "${local.name_prefix}-session"
    Service = "store-access"
  }

  depends_on = [terraform_data.network_contract]
}
