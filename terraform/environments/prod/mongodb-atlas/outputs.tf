output "atlas_project_id" {
  description = "Atlas project containing the Audit cluster."
  value       = mongodbatlas_project.this.id
}

output "atlas_cluster_name" {
  description = "Atlas cluster name."
  value       = mongodbatlas_advanced_cluster.this.name
}

output "atlas_cluster_tier" {
  description = "Atlas tier fixed for the presentation environment."
  value       = "M0"
}

output "atlas_database_access_cidr" {
  description = "Only the Terraform-managed team2 NAT public IP is allowed to connect to the Atlas database."
  value       = mongodbatlas_project_ip_access_list.eks_nat.cidr_block
}
