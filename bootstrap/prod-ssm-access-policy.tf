# Prod operators use an audited Session Manager shell only. The existing IAM
# group and membership remain account prerequisites; this Stack owns the
# project policy and its attachment to that group.

data "aws_iam_group" "team2_operators" {
  group_name = var.ssm_operator_group_name
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
  group      = data.aws_iam_group.team2_operators.group_name
  policy_arn = aws_iam_policy.prod_ssm_access.arn
}
