# Canonical GitHub Actions role for publishing Doro ERP service images to
# ECR. Doro-ERP-Service's prod Environment variable AWS_ECR_PUSH_ROLE_ARN
# points at this role's ARN.
#
# The old environment role is removed during the full rebuild. Bootstrap
# creates this canonical publisher role for the new Prod GitHub Environment.

data "aws_iam_policy_document" "doro_erp_service_ecr_publisher_assume" {
  statement {
    sid     = "AllowDoroServiceGitHubActions"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
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
        "repo:TeamDoroSoft/Doro-ERP-Service:environment:prod",
        "repo:TeamDoroSoft@305760709/Doro-ERP-Service@1314731823:environment:prod"
      ]
    }
  }
}

resource "aws_iam_role" "doro_erp_service_ecr_publisher" {
  name                 = "doro-erp-service-ecr-publisher"
  assume_role_policy   = data.aws_iam_policy_document.doro_erp_service_ecr_publisher_assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "doro_erp_service_ecr_publish" {
  statement {
    sid       = "EcrAuthorization"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PublishDoroErpImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeImages"
    ]
    resources = [
      for app in ["edge", "store-access", "commerce", "payment", "queue", "audit"] :
      "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/doro-erp-${app}"
    ]
  }
}

resource "aws_iam_policy" "doro_erp_service_ecr_publish" {
  name   = "DoroErpServiceEcrPublishPolicy"
  policy = data.aws_iam_policy_document.doro_erp_service_ecr_publish.json
}

resource "aws_iam_role_policy_attachment" "doro_erp_service_ecr_publisher" {
  role       = aws_iam_role.doro_erp_service_ecr_publisher.name
  policy_arn = aws_iam_policy.doro_erp_service_ecr_publish.arn
}
