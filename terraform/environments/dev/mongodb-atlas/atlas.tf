resource "mongodbatlas_project" "this" {
  org_id = var.atlas_org_id
  name   = var.atlas_project_name
}

resource "mongodbatlas_advanced_cluster" "this" {
  project_id                     = mongodbatlas_project.this.id
  name                           = var.atlas_cluster_name
  cluster_type                   = "REPLICASET"
  mongo_db_major_version         = "8.0"
  backup_enabled                 = true
  pit_enabled                    = true
  termination_protection_enabled = var.atlas_termination_protection_enabled

  replication_specs = [
    {
      region_configs = [
        {
          electable_specs = {
            instance_size = var.atlas_instance_size
            node_count    = 3
          }
          provider_name = "AWS"
          region_name   = "AP_NORTHEAST_2"
          priority      = 7
        }
      ]
    }
  ]

  tags = merge(local.common_tags, {
    Service = "audit"
  })
}

resource "mongodbatlas_privatelink_endpoint" "this" {
  project_id    = mongodbatlas_project.this.id
  provider_name = "AWS"
  region        = "AP_NORTHEAST_2"
}

resource "aws_security_group" "atlas_endpoint" {
  name        = "${local.name_prefix}-atlas-endpoint"
  description = "MongoDB Atlas PrivateLink access from Doro ERP EKS and SSM management."
  vpc_id      = data.aws_vpc.team2.id

  tags = {
    Name    = "${local.name_prefix}-atlas-endpoint"
    Service = "audit"
  }
}

# Atlas maps replica-set members to dynamic ports in this range.
resource "aws_vpc_security_group_ingress_rule" "atlas_from_eks" {
  security_group_id            = aws_security_group.atlas_endpoint.id
  description                  = "Atlas PrivateLink from the Dev EKS cluster"
  ip_protocol                  = "tcp"
  from_port                    = 1024
  to_port                      = 65535
  referenced_security_group_id = data.aws_eks_cluster.dev.vpc_config[0].cluster_security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "atlas_from_management" {
  security_group_id            = aws_security_group.atlas_endpoint.id
  description                  = "Atlas PrivateLink from the SSM management instance"
  ip_protocol                  = "tcp"
  from_port                    = 1024
  to_port                      = 65535
  referenced_security_group_id = data.aws_security_group.management.id
}

resource "aws_vpc_security_group_egress_rule" "atlas_all" {
  security_group_id = aws_security_group.atlas_endpoint.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_endpoint" "atlas" {
  vpc_id              = data.aws_vpc.team2.id
  service_name        = mongodbatlas_privatelink_endpoint.this.endpoint_service_name
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = false
  subnet_ids          = [data.aws_subnet.data_a.id, data.aws_subnet.data_c.id]
  security_group_ids  = [aws_security_group.atlas_endpoint.id]

  tags = {
    Name    = "${local.name_prefix}-atlas"
    Service = "audit"
  }

  depends_on = [terraform_data.network_contract]
}

resource "mongodbatlas_privatelink_endpoint_service" "this" {
  project_id          = mongodbatlas_privatelink_endpoint.this.project_id
  private_link_id     = mongodbatlas_privatelink_endpoint.this.private_link_id
  endpoint_service_id = aws_vpc_endpoint.atlas.id
  provider_name       = "AWS"
}
