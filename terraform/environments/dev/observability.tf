locals {
  container_insights_log_groups = toset([
    "application",
    "dataplane",
    "host",
    "performance"
  ])

  kubernetes_service_names = {
    for app_name in local.app_names : app_name => "${app_name}-api"
  }

  alpha_alb_cloudwatch_dimension = split("loadbalancer/", data.aws_lb.alpha.arn)[1]
}

resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = local.container_insights_log_groups

  name              = "/aws/containerinsights/${aws_eks_cluster.this.name}/${each.key}"
  retention_in_days = var.cloudwatch_log_retention_days
}

resource "aws_iam_role" "cloudwatch_observability" {
  name                 = "${local.name_prefix}-cloudwatch-observability"
  assume_role_policy   = data.aws_iam_policy_document.pod_identity_assume.json
  permissions_boundary = local.workload_boundary_arn
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability" {
  role       = aws_iam_role.cloudwatch_observability.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "amazon-cloudwatch-observability"
  addon_version = data.aws_eks_addon_version.cloudwatch_observability.version

  configuration_values = jsonencode({
    containerLogs = {
      enabled = true
    }
    containerInsights = {
      enabled = true
    }
    otelContainerInsights = {
      enabled = false
    }
    manager = {
      applicationSignals = {
        autoMonitor = {
          monitorAllServices = false
          restartPods        = false
        }
      }
    }
  })

  pod_identity_association {
    role_arn        = aws_iam_role.cloudwatch_observability.arn
    service_account = "cloudwatch-agent"
  }

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.cloudwatch_observability,
    aws_cloudwatch_log_group.container_insights,
    aws_vpc_endpoint.interface["logs"]
  ]
}

resource "aws_sns_topic" "operations" {
  name              = "${local.name_prefix}-alpha-operations"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "operations_email" {
  count = var.operations_alarm_email == null ? 0 : 1

  topic_arn = aws_sns_topic.operations.arn
  protocol  = "email"
  endpoint  = var.operations_alarm_email
}

resource "aws_cloudwatch_metric_alarm" "cluster_failed_nodes" {
  alarm_name          = "${local.name_prefix}-alpha-cluster-failed-nodes"
  alarm_description   = "At least one EKS worker node reports a failed condition."
  namespace           = "ContainerInsights"
  metric_name         = "cluster_failed_node_count"
  dimensions          = { ClusterName = aws_eks_cluster.this.name }
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Maximum"
  threshold           = 1
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.operations.arn]
  ok_actions          = [aws_sns_topic.operations.arn]

  depends_on = [aws_eks_addon.cloudwatch_observability]
}

resource "aws_cloudwatch_metric_alarm" "service_running_pods" {
  for_each = local.kubernetes_service_names

  alarm_name        = "${local.name_prefix}-alpha-${each.key}-running-pods"
  alarm_description = "${each.value} has fewer than the required two running pods."
  namespace         = "ContainerInsights"
  metric_name       = "service_number_of_running_pods"
  dimensions = {
    ClusterName = aws_eks_cluster.this.name
    Namespace   = "doro-alpha"
    Service     = each.value
  }
  comparison_operator = "LessThanThreshold"
  statistic           = "Minimum"
  threshold           = 2
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.operations.arn]
  ok_actions          = [aws_sns_topic.operations.arn]

  depends_on = [aws_eks_addon.cloudwatch_observability]
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  for_each = aws_sqs_queue.dlq

  alarm_name          = "${local.name_prefix}-alpha-${each.key}-dlq-messages"
  alarm_description   = "The ${each.key} dead-letter queue contains at least one visible message."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = each.value.name }
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Maximum"
  threshold           = 1
  period              = 60
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.operations.arn]
  ok_actions          = [aws_sns_topic.operations.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_generated_5xx" {
  alarm_name          = "${local.name_prefix}-alpha-alb-generated-5xx"
  alarm_description   = "The Dev Alpha ALB generated at least one 5xx response in five minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = { LoadBalancer = local.alpha_alb_cloudwatch_dimension }
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Sum"
  threshold           = 1
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.operations.arn]
  ok_actions          = [aws_sns_topic.operations.arn]
}

resource "aws_cloudwatch_metric_alarm" "edge_target_5xx" {
  alarm_name          = "${local.name_prefix}-alpha-edge-target-5xx"
  alarm_description   = "Edge targets returned too many 5xx responses in five minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = local.alpha_alb_cloudwatch_dimension }
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Sum"
  threshold           = var.alb_target_5xx_alarm_threshold
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.operations.arn]
  ok_actions          = [aws_sns_topic.operations.arn]
}
