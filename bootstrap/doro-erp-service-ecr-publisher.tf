# KNOWN DUPLICATE — pending consolidation review.
#
# This role/policy pair grants nothing that doro-erp-dev-github-ecr-push
# (see iam.tf) does not already grant: the ECR push scope below is a strict
# subset of that role's doro-erp-* wildcard, and the immutable GitHub OIDC
# subject used here is already allow-listed in var.github_ecr_subjects. It
# was created manually because the Doro-ERP-Service GitHub Actions workflow
# could not initially resolve the existing role.
#
# Imported as-is to bring it under Terraform state and plan visibility. The
# permissions granted in iam.tf deliberately omit iam:CreateRole /
# iam:CreatePolicy, so this pair can be deleted through Terraform but not
# recreated. Once the workflow is repointed at doro-erp-dev-github-ecr-push,
# delete this file and the matching statements in iam.tf and locals.tf.

data "aws_iam_policy_document" "doro_erp_service_ecr_publisher_assume" {
  statement {
    sid     = "AllowDoroServiceGitHubActions"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
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
        "repo:TeamDoroSoft/Doro-ERP-Service:environment:dev",
        "repo:TeamDoroSoft@305760709/Doro-ERP-Service@1314731823:environment:dev"
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
