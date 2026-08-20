data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_actions_ecr_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_service_repository}:environment:${var.github_actions_environment}"
      ]
    }
  }
}

resource "aws_iam_role" "github_actions_ecr_push" {
  name                 = "${local.name_prefix}-github-ecr-push"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_ecr_assume.json
  permissions_boundary = local.workload_boundary_arn
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_actions_ecr_push" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PublishServiceImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]
    resources = [for repository in aws_ecr_repository.app : repository.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_ecr_push" {
  name   = "publish-service-images"
  role   = aws_iam_role.github_actions_ecr_push.id
  policy = data.aws_iam_policy_document.github_actions_ecr_push.json
}
