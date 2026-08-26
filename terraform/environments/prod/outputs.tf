output "eks_cluster_name" {
  description = "EKS cluster used by the Prod Alpha cell."
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
  value       = "aws ssm start-session --target ${aws_instance.management.id} --region ${var.aws_region} --document-name ${aws_ssm_document.management_session.name}"
}

output "ssm_session_document_name" {
  description = "Audited Session Manager document allowed by the team2 operator policy."
  value       = aws_ssm_document.management_session.name
}

output "ssm_session_log_group_name" {
  description = "CloudWatch Log Group that receives management and worker SSM shell logs."
  value       = aws_cloudwatch_log_group.ssm_sessions.name
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

output "provider_admin_edge_secret_arn" {
  description = "Empty Provider Admin Edge OIDC/session Secret container to populate outside Terraform."
  value       = aws_secretsmanager_secret.provider_admin_edge.arn
}

output "provider_admin_hmac_secret_arn" {
  description = "Empty Provider Admin Edge-to-Store Access HMAC Secret container to populate outside Terraform."
  value       = aws_secretsmanager_secret.provider_admin_hmac.arn
}

output "provider_admin_edge_role_arn" {
  description = "Pod Identity IAM role for doro-provider-admin/provider-admin-edge-api only."
  value       = aws_iam_role.provider_admin_edge.arn
}

output "provider_admin_namespace" {
  description = "GitOps namespace contract for the Provider Admin frontend and dedicated Edge deployment."
  value       = local.provider_admin_namespace
}

output "provider_admin_edge_service_account" {
  description = "GitOps ServiceAccount name bound to the Provider Admin Edge Pod Identity role."
  value       = local.provider_admin_service_account
}

output "ecr_repository_urls" {
  description = "Immutable ECR repositories for the six deployable applications."
  value       = { for name, repository in aws_ecr_repository.app : name => repository.repository_url }
}

output "github_actions_ecr_push_role_arn" {
  description = "OIDC role ARN registered as the Service repository prod Environment variable AWS_ECR_PUSH_ROLE_ARN."
  value       = data.aws_iam_role.github_actions_ecr_push.arn
}

output "frontend_bucket_name" {
  description = "Private S3 bucket for the Vue SPA."
  value       = aws_s3_bucket.frontend.id
}

output "frontend_url" {
  description = "Prod Alpha public frontend URL."
  value       = "https://${var.domain_name}"
}

output "kiosk_frontend_url" {
  description = "Prod Alpha Kiosk URL served by the shared public frontend distribution."
  value       = "https://${var.kiosk_domain_name}"
}

output "frontend_ecr_repository_url" {
  description = "ECR repository URL for the Doro ERP frontend image."
  value       = aws_ecr_repository.frontend.repository_url
}

output "frontend_ecr_repository_name" {
  description = "ECR repository name registered as the Front repository prod Environment variable FRONTEND_ECR_REPOSITORY."
  value       = aws_ecr_repository.frontend.name
}

output "frontend_publisher_role_arn" {
  description = "Compatibility output for the public frontend S3 and CloudFront publisher role."
  value       = aws_iam_role.frontend_publisher.arn
}

output "frontend_public_publisher_role_arn" {
  description = "GitHub Actions role registered as AWS_FRONTEND_DEPLOY_ROLE_ARN for public S3 and CloudFront deployment."
  value       = aws_iam_role.frontend_publisher.arn
}

output "frontend_admin_ecr_publisher_role_arn" {
  description = "GitHub Actions role registered as AWS_ADMIN_ECR_PUSH_ROLE_ARN for Provider Admin image publishing."
  value       = aws_iam_role.admin_ecr_publisher.arn
}

output "frontend_cloudfront_distribution_id" {
  description = "CloudFront distribution ID invalidated after publishing the frontend artifact."
  value       = aws_cloudfront_distribution.frontend.id
}

output "route53_public_hosted_zone_id" {
  description = "Bootstrap-managed Route 53 public hosted zone ID."
  value       = data.terraform_remote_state.bootstrap.outputs.route53_public_hosted_zone_id
}

output "route53_public_hosted_zone_name_servers" {
  description = "Authoritative name servers that the domain registrar must delegate to."
  value       = data.terraform_remote_state.bootstrap.outputs.route53_public_hosted_zone_name_servers
}

output "backend_api_base_url" {
  description = "Prod Alpha API base URL routed by CloudFront to the internal ALB."
  value       = var.enable_gateway_backend ? "https://${var.domain_name}/api" : null
}

output "kiosk_backend_api_base_url" {
  description = "Prod Alpha Kiosk same-origin API base URL routed by CloudFront to the internal ALB."
  value       = var.enable_gateway_backend ? "https://${var.kiosk_domain_name}/api" : null
}

output "gateway_backend_enabled" {
  description = "Whether CloudFront, Route 53, and ALB alarms are connected to the Gateway API ALB."
  value       = var.enable_gateway_backend
}

output "alb_origin_certificate_arn" {
  description = "Regional ACM certificate discovered by the ALB Controller for its HTTPS listener."
  value       = aws_acm_certificate_validation.alpha_alb.certificate_arn
}

output "provider_admin_alb_certificate_arn" {
  description = "Regional ACM certificate ARN that GitOps must attach to the Provider Admin internal ALB HTTPS listener."
  value       = aws_acm_certificate_validation.provider_admin_alb.certificate_arn
}

output "provider_admin_alb_hostname" {
  description = "Browser Host/SNI required by the Provider Admin internal ALB. No public Route 53 ALB alias is created."
  value       = var.provider_admin_domain_name
}

output "provider_admin_alb_security_group_id" {
  description = "Security group GitOps must attach to the Provider Admin internal ALB; ingress is management EC2 SG to TCP/443 only."
  value       = aws_security_group.provider_admin_alb.id
}

output "provider_admin_port_forwarding_document_name" {
  description = "Custom SSM Session document that fixes the Provider Admin remote host, TCP/443, and local TLS port 8443."
  value       = try(aws_ssm_document.provider_admin_port_forwarding[0].name, null)
}

output "provider_admin_port_forwarding_command" {
  description = "Start the fixed-destination Provider Admin tunnel on localhost:8443; browse with provider_admin_alb_hostname as Host/SNI."
  value = var.provider_admin_remote_host == null ? null : (
    "aws ssm start-session --target ${aws_instance.management.id} --region ${var.aws_region} --document-name ${aws_ssm_document.provider_admin_port_forwarding[0].name} --parameters localPortNumber=8443"
  )
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
  description = "CloudWatch log groups that receive Prod Alpha container and Container Insights logs."
  value       = { for name, group in aws_cloudwatch_log_group.container_insights : name => group.name }
}

output "operations_alarm_topic_arn" {
  description = "SNS topic used by Prod Alpha operational alarms."
  value       = aws_sns_topic.operations.arn
}

output "cloudwatch_operations_dashboard_name" {
  description = "CloudWatch dashboard for Prod Alpha EKS, application logs, queues and alarms."
  value       = aws_cloudwatch_dashboard.operations.dashboard_name
}
