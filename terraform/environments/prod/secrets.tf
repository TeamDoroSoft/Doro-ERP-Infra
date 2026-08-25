moved {
  # Retain the existing direction-specific Secret container while changing its
  # ownership from the public-edge reader map to the Admin-only contract.
  from = aws_secretsmanager_secret.internal_hmac["edge-to-store-access-admin"]
  to   = aws_secretsmanager_secret.provider_admin_hmac
}

resource "aws_secretsmanager_secret" "service" {
  for_each = local.app_names

  name                    = "doro-erp/prod/alpha/${each.key}"
  description             = "Doro ERP Prod Alpha ${each.key} runtime secrets. Values are entered outside Terraform."
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "internal_hmac" {
  for_each = local.hmac_directions

  name                    = "doro-erp/prod/alpha/hmac/${each.key}"
  description             = "Doro ERP Prod Alpha ${each.key} HMAC secret. Values are entered outside Terraform."
  recovery_window_in_days = 7
}

# This container is intentionally separate from the public edge runtime
# secret. It contains only Provider Admin OIDC and session configuration;
# values are supplied outside Terraform.
resource "aws_secretsmanager_secret" "provider_admin_edge" {
  name                    = "doro-erp/prod/alpha/provider-admin-edge"
  description             = "Doro ERP Prod Alpha Provider Admin Edge OIDC and session secrets. Values are entered outside Terraform."
  recovery_window_in_days = 7
}

# The public edge must never read this direction-specific HMAC. Store Access
# reads it only to verify requests from the dedicated Provider Admin Edge.
resource "aws_secretsmanager_secret" "provider_admin_hmac" {
  name                    = "doro-erp/prod/alpha/hmac/edge-to-store-access-admin"
  description             = "Doro ERP Prod Alpha Provider Admin Edge to Store Access HMAC secret. Values are entered outside Terraform."
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "migration" {
  for_each = local.migration_app_names

  name                    = "doro-erp/prod/alpha/migration/${each.key}"
  description             = "Doro ERP Prod Alpha ${each.key} PostgreSQL migration credential. Values are entered outside Terraform."
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

data "aws_iam_policy_document" "provider_admin_edge" {
  statement {
    sid    = "ReadProviderAdminOidcAndSessionSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      aws_secretsmanager_secret.provider_admin_edge.arn,
      aws_secretsmanager_secret.provider_admin_hmac.arn
    ]
  }
}

data "aws_iam_policy_document" "store_access_provider_admin_hmac" {
  statement {
    sid    = "ReadProviderAdminEdgeHmac"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue"
    ]
    resources = [aws_secretsmanager_secret.provider_admin_hmac.arn]
  }
}

resource "aws_iam_role_policy" "provider_admin_edge" {
  name   = "${local.name_prefix}-provider-admin-edge-runtime"
  role   = aws_iam_role.provider_admin_edge.id
  policy = data.aws_iam_policy_document.provider_admin_edge.json
}

resource "aws_iam_role_policy" "store_access_provider_admin_hmac" {
  name   = "${local.name_prefix}-store-access-provider-admin-hmac"
  role   = aws_iam_role.workload["store-access"].id
  policy = data.aws_iam_policy_document.store_access_provider_admin_hmac.json
}

data "aws_iam_policy_document" "migration" {
  for_each = local.migration_app_names

  statement {
    sid    = "ReadOwnMigrationSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue"
    ]
    resources = [aws_secretsmanager_secret.migration[each.key].arn]
  }
}

resource "aws_iam_role_policy" "migration" {
  for_each = local.migration_app_names

  name   = "${local.name_prefix}-${each.key}-migration"
  role   = aws_iam_role.migration[each.key].id
  policy = data.aws_iam_policy_document.migration[each.key].json
}
