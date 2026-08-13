output "eks_cluster_name" {
  description = "EKS cluster used by the Dev Alpha cell."
  value       = aws_eks_cluster.this.name
}

output "eks_update_kubeconfig_command" {
  description = "CloudShell command that configures kubectl."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}

output "management_instance_id" {
  description = "SSM-only management EC2 instance ID."
  value       = aws_instance.management.id
}

output "management_session_command" {
  description = "CloudShell command that opens an SSM shell."
  value       = "aws ssm start-session --target ${aws_instance.management.id} --region ${var.aws_region}"
}

output "postgres_endpoint" {
  description = "Private RDS PostgreSQL endpoint."
  value       = aws_db_instance.postgres.address
}

output "postgres_master_secret_arn" {
  description = "RDS-managed master credential Secret ARN."
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

output "queue_urls" {
  description = "Cell-scoped FIFO main Queue URLs."
  value       = { for name, queue in aws_sqs_queue.main : name => queue.url }
}

output "queue_arns" {
  description = "Cell-scoped FIFO main Queue ARNs."
  value       = { for name, queue in aws_sqs_queue.main : name => queue.arn }
}

output "service_secret_arns" {
  description = "Empty service Secret containers to populate outside Terraform."
  value       = { for name, secret in aws_secretsmanager_secret.service : name => secret.arn }
}

output "internal_hmac_secret_arns" {
  description = "Direction-scoped internal HMAC Secrets."
  value       = { for name, secret in aws_secretsmanager_secret.internal_hmac : name => secret.arn }
}

output "ecr_repository_urls" {
  description = "Immutable ECR repositories for the six deployable applications."
  value       = { for name, repository in aws_ecr_repository.app : name => repository.repository_url }
}

output "frontend_bucket_name" {
  description = "Private S3 bucket for the Vue SPA."
  value       = aws_s3_bucket.frontend.id
}

output "frontend_url" {
  description = "Dev Alpha public frontend URL."
  value       = "https://${var.domain_name}"
}
