output "atlas_project_id" {
  description = "Atlas project containing the Audit cluster."
  value       = mongodbatlas_project.this.id
}

output "atlas_cluster_name" {
  description = "Atlas cluster name."
  value       = mongodbatlas_advanced_cluster.this.name
}

output "atlas_private_link_id" {
  description = "Atlas PrivateLink connection ID."
  value       = mongodbatlas_privatelink_endpoint.this.private_link_id
}

output "aws_vpc_endpoint_id" {
  description = "AWS interface endpoint connected to Atlas."
  value       = aws_vpc_endpoint.atlas.id
}

output "atlas_private_link_status" {
  description = "Atlas-side private endpoint status."
  value       = mongodbatlas_privatelink_endpoint.this.status
}
