data "aws_iam_policy_document" "frontend_publisher_assume" {
  statement {
    sid     = "AllowDoroFrontendGitHubActions"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.bootstrap.outputs.github_actions_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:TeamDoroSoft/Doro-ERP-Front:environment:prod"]
    }
  }
}

resource "aws_iam_role" "frontend_publisher" {
  name                 = "${local.name_prefix}-frontend-publisher"
  description          = "GitHub Actions role for publishing the Doro ERP frontend to ECR and S3."
  assume_role_policy   = data.aws_iam_policy_document.frontend_publisher_assume.json
  permissions_boundary = local.workload_boundary_arn
  max_session_duration = 3600
}

data "aws_iam_policy_document" "frontend_publish" {
  statement {
    sid       = "EcrAuthorization"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PublishFrontendImage"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]
    resources = [aws_ecr_repository.frontend.arn]
  }

  statement {
    sid    = "ReadFrontendBucketMetadata"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]
    resources = [aws_s3_bucket.frontend.arn]
  }

  statement {
    sid    = "DeployFrontendObjects"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]
  }

  statement {
    sid    = "InvalidateFrontendDistribution"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation"
    ]
    resources = [aws_cloudfront_distribution.frontend.arn]
  }
}

resource "aws_iam_role_policy" "frontend_publish" {
  name   = "DoroERPProdFrontendPublishPolicy"
  role   = aws_iam_role.frontend_publisher.id
  policy = data.aws_iam_policy_document.frontend_publish.json
}
