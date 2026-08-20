resource "aws_iam_group" "team2_doro_load" {
  name = "team2-doro-load-group"
}

data "aws_iam_policy_document" "team2_doro_load_eks_console_access" {
  statement {
    sid    = "EksConsoleAndKubernetesApiAccess"
    effect = "Allow"
    actions = [
      "eks:ListClusters",
      "eks:DescribeCluster",
      "eks:ListNodegroups",
      "eks:DescribeNodegroup",
      "eks:ListFargateProfiles",
      "eks:ListUpdates",
      "eks:ListAddons",
      "eks:DescribeAddon",
      "eks:DescribeAddonVersions",
      "eks:ListIdentityProviderConfigs",
      "eks:AccessKubernetesApi"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_group_policy" "team2_doro_load_eks_console_access" {
  name   = "EKS-Direct-Console-Access"
  group  = aws_iam_group.team2_doro_load.name
  policy = data.aws_iam_policy_document.team2_doro_load_eks_console_access.json
}

data "aws_iam_policy_document" "team2_doro_load_ecr_push" {
  statement {
    sid       = "EcrAuthentication"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushDoroSpringApi"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeImages",
      "ecr:ListImages"
    ]
    resources = ["arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/team2/doroload"]
  }
}

resource "aws_iam_group_policy" "team2_doro_load_ecr_push" {
  name   = "team2-doro-load-ecr-push-policy"
  group  = aws_iam_group.team2_doro_load.name
  policy = data.aws_iam_policy_document.team2_doro_load_ecr_push.json
}

data "aws_iam_policy_document" "team2_doro_load_s3_frontend" {
  statement {
    sid       = "ListFrontendBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::team2-doro-s3-front"]
  }

  statement {
    sid    = "SyncFrontendBucketObjects"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = ["arn:aws:s3:::team2-doro-s3-front/*"]
  }
}

resource "aws_iam_group_policy" "team2_doro_load_s3_frontend" {
  name   = "team2-doro-load-s3-frontend-policy"
  group  = aws_iam_group.team2_doro_load.name
  policy = data.aws_iam_policy_document.team2_doro_load_s3_frontend.json
}

resource "aws_iam_group_policy_attachment" "team2_doro_load_ssm_access" {
  group      = aws_iam_group.team2_doro_load.name
  policy_arn = "arn:aws:iam::${var.aws_account_id}:policy/team2-doroload-ssm-access-policy"
}

# Authoritative membership list: applying this resource removes any group
# member not listed here. Confirm the live membership matches before apply.
resource "aws_iam_group_membership" "team2_doro_load" {
  name  = "team2-doro-load-group-membership"
  group = aws_iam_group.team2_doro_load.name
  users = [
    "a-student-02",
    "a-student-06",
    "b-student-11",
    "b-student-05",
    "cld-team2-doro-github-action"
  ]
}
