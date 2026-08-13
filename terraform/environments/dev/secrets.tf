resource "aws_secretsmanager_secret" "service" {
  for_each = local.app_names

  name                    = "doro-erp/dev/alpha/${each.key}"
  description             = "Doro ERP Dev Alpha ${each.key} runtime secrets. Values are entered outside Terraform."
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "internal_hmac" {
  for_each = local.hmac_directions

  name                    = "doro-erp/dev/alpha/hmac/${each.key}"
  description             = "Doro ERP Dev Alpha ${each.key} HMAC secret. Values are entered outside Terraform."
  recovery_window_in_days = 7
}

data "aws_iam_policy_document" "workload" {
  for_each = local.app_names

  statement {
    sid    = "ReadOwnRuntimeSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue"
    ]
    resources = concat(
      [aws_secretsmanager_secret.service[each.key].arn],
      [
        for direction, readers in local.hmac_directions :
        aws_secretsmanager_secret.internal_hmac[direction].arn
        if contains(readers, each.key)
      ]
    )
  }

  dynamic "statement" {
    for_each = length(local.sqs_send[each.key]) == 0 ? [] : [1]
    content {
      sid       = "SendApprovedQueues"
      effect    = "Allow"
      actions   = ["sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:SendMessage"]
      resources = [for queue_name in local.sqs_send[each.key] : aws_sqs_queue.main[queue_name].arn]
    }
  }

  dynamic "statement" {
    for_each = length(local.sqs_receive[each.key]) == 0 ? [] : [1]
    content {
      sid    = "ConsumeOwnedQueue"
      effect = "Allow"
      actions = [
        "sqs:ChangeMessageVisibility",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:ReceiveMessage"
      ]
      resources = [for queue_name in local.sqs_receive[each.key] : aws_sqs_queue.main[queue_name].arn]
    }
  }
}

resource "aws_iam_role_policy" "workload" {
  for_each = local.app_names

  name   = "${local.name_prefix}-${each.key}-runtime"
  role   = aws_iam_role.workload[each.key].id
  policy = data.aws_iam_policy_document.workload[each.key].json
}
