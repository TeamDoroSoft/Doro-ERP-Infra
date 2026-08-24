output "vpc_id" {
  description = "Terraform-managed Prod VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Prod VPC IPv4 CIDR."
  value       = aws_vpc.this.cidr_block
}

output "internet_gateway_id" {
  description = "The single Internet Gateway attached to the Prod VPC."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_id" {
  description = "The single cost-optimized Prod NAT Gateway."
  value       = aws_nat_gateway.this.id
}

output "nat_public_ip" {
  description = "Stable NAT EIP that must be allow-listed in MongoDB Atlas."
  value       = aws_eip.nat.public_ip
}

output "subnet_ids" {
  description = "Subnet IDs grouped by their stable logical names."
  value       = { for name, subnet in aws_subnet.this : name => subnet.id }
}

output "subnet_names" {
  description = "Stable subnet Name tags for Kubernetes Gateway API configuration."
  value       = { for name, subnet in aws_subnet.this : name => subnet.tags["Name"] }
}

output "route_table_ids" {
  description = "Route table IDs grouped by network tier."
  value = {
    public = aws_route_table.public.id
    app    = aws_route_table.app.id
    data   = aws_route_table.data.id
  }
}

output "interface_endpoint_security_group_id" {
  description = "Security group shared by the private Interface VPC Endpoints."
  value       = aws_security_group.interface_endpoints.id
}

output "interface_endpoint_ids" {
  description = "Interface VPC Endpoint IDs by AWS service short name."
  value       = { for name, endpoint in aws_vpc_endpoint.interface : name => endpoint.id }
}
