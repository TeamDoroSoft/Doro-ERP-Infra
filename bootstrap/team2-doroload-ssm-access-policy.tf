# team2-doroload-ssm-access-policy — only the policy content is managed here.
#
# This is the one policy still in active use on team2-doro-load-group (SSM
# session access to Team=team2-tagged EC2 instances, which today only means
# doro-erp-dev-management). The group itself, its membership, and its other
# three inline policies (EKS-Direct-Console-Access, team2-doro-load-ecr-push-
# policy, team2-doro-load-s3-frontend-policy) target either unused or already
# -deleted resources from the retired DoroLoad project and are intentionally
# left unmanaged — see Docs/IAM_리소스_정리_및_Bootstrap_State_협의사항.md.
# The attachment to the group is also left unmanaged; only the policy's own
# content is under Terraform.

data "aws_iam_policy_document" "team2_doroload_ssm_access" {
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
    sid       = "UseShellSessionDocument"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:document/SSM-SessionManagerRunShell"]
  }

  statement {
    sid       = "UseSSHSessionDocument"
    effect    = "Allow"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ssm:*:*:document/AWS-StartSSHSession"]
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

resource "aws_iam_policy" "team2_doroload_ssm_access" {
  name   = "team2-doroload-ssm-access-policy"
  policy = data.aws_iam_policy_document.team2_doroload_ssm_access.json
}
