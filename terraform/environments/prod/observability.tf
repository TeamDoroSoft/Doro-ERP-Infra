locals {
  container_insights_log_groups = toset([
    "application",
    "dataplane",
    "host",
    "performance"
  ])

  kubernetes_services = merge(
    {
      for app_name in local.app_names : app_name => {
        namespace = "doro-alpha"
        service   = "${app_name}-api"
      }
    },
    {
      provider-admin = {
        namespace = "doro-provider-admin"
        service   = "provider-admin"
      }
      provider-admin-edge = {
        namespace = "doro-provider-admin"
        service   = "provider-admin-edge-api"
      }
    }
  )

  alpha_alb_cloudwatch_dimension = var.enable_gateway_backend ? split("loadbalancer/", data.aws_lb.gateway[0].arn)[1] : null
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
    terraform_data.network_contract
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
  for_each = local.kubernetes_services

  alarm_name        = "${local.name_prefix}-alpha-${each.key}-running-pods"
  alarm_description = "${each.value.service} has fewer than the required two running pods."
  namespace         = "ContainerInsights"
  metric_name       = "service_number_of_running_pods"
  dimensions = {
    ClusterName = aws_eks_cluster.this.name
    Namespace   = each.value.namespace
    Service     = each.value.service
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
  count = var.enable_gateway_backend ? 1 : 0

  alarm_name          = "${local.name_prefix}-alpha-alb-generated-5xx"
  alarm_description   = "The Prod Alpha ALB generated at least one 5xx response in five minutes."
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
  count = var.enable_gateway_backend ? 1 : 0

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

resource "aws_cloudwatch_query_definition" "application_errors" {
  name = "${local.name_prefix}/alpha/application-errors"

  log_group_names = [aws_cloudwatch_log_group.container_insights["application"].name]

  query_string = <<-QUERY
    fields @timestamp, kubernetes.namespace_name, kubernetes.pod_name, kubernetes.container_name, log
    | filter kubernetes.namespace_name in ["doro-alpha", "doro-provider-admin", "argocd"]
    | filter log like /ERROR|Exception|INTERNAL_SERVER_ERROR|DEPENDENCY_UNAVAILABLE/
    | sort @timestamp desc
    | limit 200
  QUERY
}

resource "aws_cloudwatch_query_definition" "application_request_trace" {
  name = "${local.name_prefix}/alpha/request-trace-template"

  log_group_names = [aws_cloudwatch_log_group.container_insights["application"].name]

  query_string = <<-QUERY
    fields @timestamp, kubernetes.namespace_name, kubernetes.pod_name, kubernetes.container_name, log
    | filter log like /REPLACE_WITH_REQUEST_ID/
    | sort @timestamp asc
    | limit 200
  QUERY
}

resource "aws_cloudwatch_dashboard" "operations" {
  dashboard_name = "${local.name_prefix}-alpha-operations"

  dashboard_body = jsonencode({
    widgets = concat(
      [
        {
          type   = "text"
          x      = 0
          y      = 0
          width  = 24
          height = 2
          properties = {
            markdown = "# Doro ERP Prod Alpha\nEKS 상태는 **doro-erp-prod**, Application Log는 **${aws_cloudwatch_log_group.container_insights["application"].name}**에서 확인합니다."
          }
        },
        {
          type   = "metric"
          x      = 0
          y      = 2
          width  = 8
          height = 6
          properties = {
            title  = "EKS Failed Nodes"
            region = var.aws_region
            view   = "timeSeries"
            stat   = "Maximum"
            period = 60
            metrics = [
              [
                "ContainerInsights",
                "cluster_failed_node_count",
                "ClusterName",
                aws_eks_cluster.this.name,
                { label = "Failed nodes" }
              ]
            ]
          }
        },
        {
          type   = "metric"
          x      = 8
          y      = 2
          width  = 16
          height = 6
          properties = {
            title  = "Prod Alpha Running Pods"
            region = var.aws_region
            view   = "timeSeries"
            stat   = "Minimum"
            period = 60
            metrics = [
              for app_name, workload in local.kubernetes_services : [
                "ContainerInsights",
                "service_number_of_running_pods",
                "ClusterName",
                aws_eks_cluster.this.name,
                "Namespace",
                workload.namespace,
                "Service",
                workload.service,
                { label = app_name }
              ]
            ]
          }
        },
        {
          type   = "metric"
          x      = 0
          y      = 8
          width  = 12
          height = 6
          properties = {
            title  = "Dead-letter Queue Messages"
            region = var.aws_region
            view   = "timeSeries"
            stat   = "Maximum"
            period = 60
            metrics = [
              for queue_name, queue in aws_sqs_queue.dlq : [
                "AWS/SQS",
                "ApproximateNumberOfMessagesVisible",
                "QueueName",
                queue.name,
                { label = queue_name }
              ]
            ]
          }
        },
        {
          type   = "alarm"
          x      = 12
          y      = 8
          width  = 12
          height = 6
          properties = {
            title = "Operational Alarm Status"
            alarms = concat(
              [aws_cloudwatch_metric_alarm.cluster_failed_nodes.arn],
              [for alarm in aws_cloudwatch_metric_alarm.service_running_pods : alarm.arn],
              [for alarm in aws_cloudwatch_metric_alarm.dlq_messages : alarm.arn],
              [for alarm in aws_cloudwatch_metric_alarm.alb_generated_5xx : alarm.arn],
              [for alarm in aws_cloudwatch_metric_alarm.edge_target_5xx : alarm.arn]
            )
          }
        },
        {
          type   = "log"
          x      = 0
          y      = 14
          width  = 24
          height = 8
          properties = {
            title  = "Recent Application Errors"
            region = var.aws_region
            view   = "table"
            query  = <<-QUERY
              SOURCE '${aws_cloudwatch_log_group.container_insights["application"].name}'
              | fields @timestamp, kubernetes.namespace_name, kubernetes.pod_name, kubernetes.container_name, log
              | filter kubernetes.namespace_name in ["doro-alpha", "doro-provider-admin", "argocd"]
              | filter log like /ERROR|Exception|INTERNAL_SERVER_ERROR|DEPENDENCY_UNAVAILABLE/
              | sort @timestamp desc
              | limit 100
            QUERY
          }
        },
        {
          type   = "metric"
          x      = 0
          y      = 28
          width  = 12
          height = 6
          properties = {
            title  = "EKS Node CPU and Memory"
            region = var.aws_region
            view   = "timeSeries"
            period = 300
            metrics = [
              [
                {
                  expression = "SEARCH('{ContainerInsights,ClusterName,NodeName} MetricName=\"node_cpu_utilization\" ClusterName=\"${aws_eks_cluster.this.name}\"', 'Average', 300)"
                  id         = "nodecpu"
                  label      = "Node CPU"
                }
              ],
              [
                {
                  expression = "SEARCH('{ContainerInsights,ClusterName,NodeName} MetricName=\"node_memory_utilization\" ClusterName=\"${aws_eks_cluster.this.name}\"', 'Average', 300)"
                  id         = "nodememory"
                  label      = "Node Memory"
                }
              ]
            ]
            yAxis = {
              left = {
                min   = 0
                max   = 100
                label = "Percent"
              }
            }
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 28
          width  = 12
          height = 6
          properties = {
            title  = "Doro ERP Pod Health Signals"
            region = var.aws_region
            view   = "timeSeries"
            period = 300
            metrics = [
              [
                {
                  expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_number_of_container_restarts\" ClusterName=\"${aws_eks_cluster.this.name}\" (Namespace=\"doro-alpha\" OR Namespace=\"doro-provider-admin\")', 'Maximum', 300)"
                  id         = "restarts"
                  label      = "Container restarts"
                }
              ],
              [
                {
                  expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_status_pending\" ClusterName=\"${aws_eks_cluster.this.name}\" (Namespace=\"doro-alpha\" OR Namespace=\"doro-provider-admin\")', 'Maximum', 300)"
                  id         = "pending"
                  label      = "Pending pods"
                }
              ],
              [
                {
                  expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_container_status_waiting_reason_crash_loop_back_off\" ClusterName=\"${aws_eks_cluster.this.name}\" (Namespace=\"doro-alpha\" OR Namespace=\"doro-provider-admin\")', 'Maximum', 300)"
                  id         = "crashloop"
                  label      = "CrashLoopBackOff"
                }
              ],
              [
                {
                  expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_container_status_waiting_reason_image_pull_error\" ClusterName=\"${aws_eks_cluster.this.name}\" (Namespace=\"doro-alpha\" OR Namespace=\"doro-provider-admin\")', 'Maximum', 300)"
                  id         = "imagepull"
                  label      = "Image pull errors"
                }
              ]
            ]
          }
        },
        {
          type   = "metric"
          x      = 0
          y      = 34
          width  = 12
          height = 6
          properties = {
            title  = "PostgreSQL Health"
            region = var.aws_region
            view   = "timeSeries"
            period = 300
            metrics = [
              ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.postgres.identifier, { label = "CPU %", stat = "Average" }],
              ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.postgres.identifier, { label = "Connections", stat = "Average", yAxis = "right" }],
              ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.postgres.identifier, { label = "Free storage", stat = "Minimum", yAxis = "right" }],
              ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", aws_db_instance.postgres.identifier, { label = "Free memory", stat = "Minimum", yAxis = "right" }]
            ]
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 34
          width  = 12
          height = 6
          properties = {
            title  = "CloudFront Traffic and Errors"
            region = "us-east-1"
            view   = "timeSeries"
            period = 300
            metrics = [
              ["AWS/CloudFront", "Requests", "DistributionId", aws_cloudfront_distribution.frontend.id, "Region", "Global", { label = "Requests", stat = "Sum" }],
              ["AWS/CloudFront", "4xxErrorRate", "DistributionId", aws_cloudfront_distribution.frontend.id, "Region", "Global", { label = "4xx rate", stat = "Average", yAxis = "right" }],
              ["AWS/CloudFront", "5xxErrorRate", "DistributionId", aws_cloudfront_distribution.frontend.id, "Region", "Global", { label = "5xx rate", stat = "Average", yAxis = "right" }]
            ]
          }
        },
        {
          type   = "metric"
          x      = 0
          y      = 40
          width  = 24
          height = 6
          properties = {
            title  = "Doro ERP Pod CPU and Memory"
            region = var.aws_region
            view   = "timeSeries"
            period = 300
            metrics = [
              [
                {
                  expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_cpu_utilization\" ClusterName=\"${aws_eks_cluster.this.name}\" (Namespace=\"doro-alpha\" OR Namespace=\"doro-provider-admin\")', 'Average', 300)"
                  id         = "podcpu"
                  label      = "Pod CPU"
                }
              ],
              [
                {
                  expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_memory_utilization\" ClusterName=\"${aws_eks_cluster.this.name}\" (Namespace=\"doro-alpha\" OR Namespace=\"doro-provider-admin\")', 'Average', 300)"
                  id         = "podmemory"
                  label      = "Pod Memory"
                }
              ]
            ]
            yAxis = {
              left = {
                min   = 0
                max   = 100
                label = "Percent"
              }
            }
          }
        },
        {
          type   = "metric"
          x      = 0
          y      = 46
          width  = 24
          height = 6
          properties = {
            title  = "ElastiCache Redis Health"
            region = var.aws_region
            view   = "timeSeries"
            period = 300
            metrics = [
              ["AWS/ElastiCache", "EngineCPUUtilization", "CacheClusterId", "${local.name_prefix}-alpha-session-001", { label = "Engine CPU %", stat = "Average" }],
              ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", "CacheClusterId", "${local.name_prefix}-alpha-session-001", { label = "Memory usage %", stat = "Average" }],
              ["AWS/ElastiCache", "CurrConnections", "CacheClusterId", "${local.name_prefix}-alpha-session-001", { label = "Connections", stat = "Average", yAxis = "right" }],
              ["AWS/ElastiCache", "Evictions", "CacheClusterId", "${local.name_prefix}-alpha-session-001", { label = "Evictions", stat = "Sum", yAxis = "right" }]
            ]
          }
        }
      ],
      var.enable_gateway_backend ? [
        {
          type   = "metric"
          x      = 0
          y      = 22
          width  = 24
          height = 6
          properties = {
            title  = "Gateway ALB 5xx"
            region = var.aws_region
            view   = "timeSeries"
            stat   = "Sum"
            period = 300
            metrics = [
              [
                "AWS/ApplicationELB",
                "HTTPCode_ELB_5XX_Count",
                "LoadBalancer",
                local.alpha_alb_cloudwatch_dimension,
                { label = "ALB generated 5xx" }
              ],
              [
                "AWS/ApplicationELB",
                "HTTPCode_Target_5XX_Count",
                "LoadBalancer",
                local.alpha_alb_cloudwatch_dimension,
                { label = "Target generated 5xx" }
              ]
            ]
          }
        }
      ] : []
    )
  })
}
