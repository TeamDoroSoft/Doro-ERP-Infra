resource "aws_cloudwatch_log_group" "ssm_sessions" {
  name              = "/doro-erp/prod/ssm-sessions"
  retention_in_days = 30

  tags = {
    Name = "${local.name_prefix}-ssm-sessions"
  }
}

resource "aws_ssm_document" "management_session" {
  name            = "${local.name_prefix}-session"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Audited shell access to the Doro ERP Prod management instance."
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = ""
      s3KeyPrefix                 = ""
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.ssm_sessions.name
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = true
      kmsKeyId                    = ""
      runAsEnabled                = false
      runAsDefaultUser            = ""
      idleSessionTimeout          = "20"
      maxSessionDuration          = "60"
      shellProfile = {
        windows = ""
        linux   = ""
      }
    }
  })

  tags = {
    Name = "${local.name_prefix}-session"
  }
}

data "aws_iam_policy_document" "session_logs" {
  statement {
    sid    = "DescribeSessionLogGroups"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "WriteSessionLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.ssm_sessions.arn}:*"]
  }
}

resource "aws_iam_role_policy" "session_logs" {
  for_each = {
    management = aws_iam_role.management_instance.name
    eks-node   = aws_iam_role.eks_node.name
  }

  name   = "DoroERPDevSessionLogPolicy"
  role   = each.value
  policy = data.aws_iam_policy_document.session_logs.json
}
