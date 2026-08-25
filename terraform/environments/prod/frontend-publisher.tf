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
  description          = "GitHub Actions role for deploying the public Doro ERP frontend to S3 and CloudFront."
  assume_role_policy   = data.aws_iam_policy_document.frontend_publisher_assume.json
  permissions_boundary = local.workload_boundary_arn
  max_session_duration = 3600
}

data "aws_iam_policy_document" "frontend_publish" {
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
  name   = "DoroERPProdFrontendPublicPublishPolicy"
  role   = aws_iam_role.frontend_publisher.id
  policy = data.aws_iam_policy_document.frontend_publish.json
}

resource "aws_iam_role" "admin_ecr_publisher" {
  name                 = "${local.name_prefix}-admin-ecr-publisher"
  description          = "GitHub Actions role for publishing the Provider Admin image to its ECR repository."
  assume_role_policy   = data.aws_iam_policy_document.frontend_publisher_assume.json
  permissions_boundary = local.workload_boundary_arn
  max_session_duration = 3600
}

data "aws_iam_policy_document" "admin_ecr_publish" {
  statement {
    sid       = "EcrAuthorization"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PublishProviderAdminImage"
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
}

resource "aws_iam_role_policy" "admin_ecr_publish" {
  name   = "DoroERPProdAdminEcrPublishPolicy"
  role   = aws_iam_role.admin_ecr_publisher.id
  policy = data.aws_iam_policy_document.admin_ecr_publish.json
}
