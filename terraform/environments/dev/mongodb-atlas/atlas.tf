resource "mongodbatlas_project" "this" {
  org_id = var.atlas_org_id
  name   = var.atlas_project_name
}

resource "mongodbatlas_advanced_cluster" "this" {
  project_id   = mongodbatlas_project.this.id
  name         = var.atlas_cluster_name
  cluster_type = "REPLICASET"

  replication_specs = [
    {
      region_configs = [
        {
          electable_specs = {
            instance_size = "M0"
          }
          provider_name         = "TENANT"
          backing_provider_name = "AWS"
          region_name           = var.atlas_region
          priority              = 7
        }
      ]
    }
  ]

  tags = merge(local.common_tags, {
    Service = "audit"
  })
}

resource "mongodbatlas_project_ip_access_list" "eks_nat" {
  project_id = mongodbatlas_project.this.id
  cidr_block = "${data.aws_nat_gateway.dev.public_ip}/32"
  comment    = "Doro ERP Dev EKS and SSM management through the team2 NAT Gateway"
}
