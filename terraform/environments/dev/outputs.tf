output "eks_cluster_name" {
  description = "EKS cluster used by the Dev Alpha cell."
  value       = aws_eks_cluster.this.name
}

output "eks_update_kubeconfig_command" {
  description = "CloudShell command that configures kubectl."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}

output "load_balancer_controller_role_arn" {
  description = "Pod Identity IAM role used by the AWS Load Balancer Controller."
  value       = aws_iam_role.load_balancer_controller.arn
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

output "migration_secret_arns" {
  description = "Secrets Manager ARNs for the four PostgreSQL migration credentials."
  value       = { for name, secret in aws_secretsmanager_secret.migration : name => secret.arn }
}

output "internal_hmac_secret_arns" {
  description = "Direction-scoped internal HMAC Secrets."
  value       = { for name, secret in aws_secretsmanager_secret.internal_hmac : name => secret.arn }
}

output "ecr_repository_urls" {
  description = "Immutable ECR repositories for the six deployable applications."
  value       = { for name, repository in aws_ecr_repository.app : name => repository.repository_url }
}

output "github_actions_ecr_push_role_arn" {
  description = "OIDC role ARN registered as the Service repository dev Environment variable AWS_ECR_PUSH_ROLE_ARN."
  value       = data.aws_iam_role.github_actions_ecr_push.arn
}

output "frontend_bucket_name" {
  description = "Private S3 bucket for the Vue SPA."
  value       = aws_s3_bucket.frontend.id
}

output "frontend_url" {
  description = "Dev Alpha public frontend URL."
  value       = "https://${var.domain_name}"
}

output "backend_api_base_url" {
  description = "Dev Alpha API base URL routed by CloudFront to the internal ALB."
  value       = var.enable_gateway_backend ? "https://${var.domain_name}/api" : null
}

output "gateway_backend_enabled" {
  description = "Whether CloudFront, Route 53, and ALB alarms are connected to the Gateway API ALB."
  value       = var.enable_gateway_backend
}

output "alb_origin_certificate_arn" {
  description = "Regional ACM certificate discovered by the ALB Controller for its HTTPS listener."
  value       = aws_acm_certificate_validation.alpha_alb.certificate_arn
}

output "alb_origin_hostname" {
  description = "TLS-validated CloudFront VPC origin hostname for the internal ALB."
  value       = var.alb_origin_domain_name
}

output "gateway_alb_name" {
  description = "Internal ALB name provisioned by the AWS Load Balancer Controller Gateway API."
  value       = var.enable_gateway_backend ? data.aws_lb.gateway[0].name : null
}

output "gateway_alb_dns_name" {
  description = "Internal ALB DNS name provisioned by the AWS Load Balancer Controller Gateway API."
  value       = var.enable_gateway_backend ? data.aws_lb.gateway[0].dns_name : null
}

output "gateway_alb_security_group_id" {
  description = "Terraform-managed frontend security group attached to the Gateway API ALB."
  value       = aws_security_group.alpha_alb_frontend.id
}

output "cloudwatch_container_log_groups" {
  description = "CloudWatch log groups that receive Dev Alpha container and Container Insights logs."
  value       = { for name, group in aws_cloudwatch_log_group.container_insights : name => group.name }
}

output "operations_alarm_topic_arn" {
  description = "SNS topic used by Dev Alpha operational alarms."
  value       = aws_sns_topic.operations.arn
}
