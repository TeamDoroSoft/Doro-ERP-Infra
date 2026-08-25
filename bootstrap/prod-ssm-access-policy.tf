# Prod operators use an audited Session Manager shell only. IAM users remain
# account prerequisites; this Stack owns the group, its exact membership, the
# project policy and the policy attachment.

resource "aws_iam_group" "team2_operators" {
  name = var.ssm_operator_group_name
}

resource "aws_iam_group_membership" "team2_operators" {
  name  = "${var.ssm_operator_group_name}-membership"
  group = aws_iam_group.team2_operators.name
  users = sort(tolist(var.ssm_operator_user_names))
}

data "aws_iam_policy_document" "prod_ssm_access" {
  statement {
    sid       = "StartSessionToTeam2Instances"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Team"
      values   = ["team2"]
    }
  }

  statement {
    sid       = "UseAuditedShellSessionDocument"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:document/doro-erp-prod-session"]
  }

  # The remote host and port are fixed in this custom Session document. The
  # document permission is deliberately paired with the one management EC2
  # target, so it cannot be used as a general VPC proxy.
  statement {
    sid       = "StartProviderAdminPortForwardingOnlyToManagement"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Name"
      values   = ["doro-erp-prod-management"]
    }
  }

  statement {
    sid       = "UseFixedProviderAdminPortForwardingDocument"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:document/doro-erp-prod-provider-admin-port-forwarding"]
  }

  statement {
    sid       = "OpenOwnSessionDataChannel"
    effect    = "Allow"
    actions   = ["ssmmessages:OpenDataChannel"]
    resources = ["arn:aws:ssm:*:*:session/$${aws:userid}-*"]
  }

  statement {
    sid    = "ViewManagedInstancesAndSessions"
    effect = "Allow"
    actions = [
      "ssm:DescribeSessions",
      "ssm:GetConnectionStatus",
      "ssm:DescribeInstanceInformation",
      "ssm:DescribeInstanceProperties",
      "ec2:DescribeInstances"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ManageOwnSessions"
    effect    = "Allow"
    actions   = ["ssm:TerminateSession", "ssm:ResumeSession"]
    resources = ["arn:aws:ssm:*:*:session/$${aws:userid}-*"]
  }
}

resource "aws_iam_policy" "prod_ssm_access" {
  name        = "doro-erp-prod-ssm-access"
  description = "Audited Session Manager access to Team=team2 Prod EC2 instances."
  policy      = data.aws_iam_policy_document.prod_ssm_access.json
}

resource "aws_iam_group_policy_attachment" "prod_ssm_access" {
  group      = aws_iam_group.team2_operators.name
  policy_arn = aws_iam_policy.prod_ssm_access.arn
}
