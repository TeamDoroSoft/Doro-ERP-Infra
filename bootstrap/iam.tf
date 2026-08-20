data "aws_iam_policy_document" "workload_boundary" {
  statement {
    sid    = "AllowAwsWorkloadActions"
    effect = "Allow"

    not_actions = [
      "account:*",
      "iam:*",
      "organizations:*"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name        = local.workload_boundary_name
  description = "Permissions boundary for Doro ERP dev workload and service roles."
  policy      = data.aws_iam_policy_document.workload_boundary.json
}

data "aws_iam_policy_document" "terraform_assume_role" {
  statement {
    sid     = "AllowApprovedTerraformOperators"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = sort(tolist(var.terraform_operator_principal_arns))
    }

    condition {
      test     = "StringLike"
      variable = "sts:RoleSessionName"
      values   = ["doro-erp-dev-*"]
    }
  }
}

resource "aws_iam_role" "terraform_execution" {
  name                 = local.terraform_role_name
  description          = "Terraform execution role for the Doro ERP dev environment."
  assume_role_policy   = data.aws_iam_policy_document.terraform_assume_role.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "terraform_iam_management" {
  statement {
    sid    = "ManageTerraformState"
    effect = "Allow"
    actions = [
      "s3:GetBucketVersioning",
      "s3:ListBucket"
    ]
    resources = [aws_s3_bucket.terraform_state.arn]
  }

  statement {
    sid    = "ManageTerraformStateObjects"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject"
    ]
    resources = ["${aws_s3_bucket.terraform_state.arn}/*"]
  }

  statement {
    sid    = "ReadIamMetadata"
    effect = "Allow"
    actions = [
      "iam:GetInstanceProfile",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListPolicyVersions",
      "iam:ListRolePolicies",
      "iam:ListRoles"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CreateBoundedProjectRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:TagRole"
    ]
    resources = [local.project_role_arn_pattern]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.workload_boundary_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [local.common_tags.Project]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [local.common_tags.Environment]
    }
  }

  statement {
    sid    = "ManageProjectRoles"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription"
    ]
    resources = [local.project_role_arn_pattern]
  }

  statement {
    sid    = "ManageProjectInstanceProfiles"
    effect = "Allow"
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile"
    ]
    resources = [local.project_instance_profile_arn_pattern]
  }

  statement {
    sid    = "ManageProjectPolicies"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy"
    ]
    resources = [local.project_policy_arn_pattern]
  }

  statement {
    sid    = "ManageTeam2DoroLoadGroup"
    effect = "Allow"
    actions = [
      "iam:AddUserToGroup",
      "iam:AttachGroupPolicy",
      "iam:CreateGroup",
      "iam:DeleteGroup",
      "iam:DeleteGroupPolicy",
      "iam:DetachGroupPolicy",
      "iam:GetGroup",
      "iam:GetGroupPolicy",
      "iam:ListAttachedGroupPolicies",
      "iam:ListGroupPolicies",
      "iam:PutGroupPolicy",
      "iam:RemoveUserFromGroup",
      "iam:TagGroup",
      "iam:UntagGroup"
    ]
    resources = [local.team2_doro_load_group_arn]
  }

  # Known duplicate of doro-erp-dev-github-ecr-push, imported as-is pending
  # consolidation review. iam:CreateRole/iam:CreatePolicy are deliberately
  # omitted: Terraform can manage or delete this pair but not recreate it.
  # See bootstrap/doro-erp-service-ecr-publisher.tf.
  statement {
    sid    = "ManageDoroErpServiceEcrPublisher"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DeleteRole",
      "iam:DetachRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription"
    ]
    resources = [local.doro_erp_service_ecr_publisher_role_arn]
  }

  statement {
    sid    = "ManageDoroErpServiceEcrPublishPolicy"
    effect = "Allow"
    actions = [
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy"
    ]
    resources = [local.doro_erp_service_ecr_publish_policy_arn]
  }

  statement {
    sid     = "PassBoundedProjectRoles"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      local.project_role_arn_pattern
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values = [
        "ec2.amazonaws.com",
        "eks.amazonaws.com",
        "events.amazonaws.com",
        "pods.eks.amazonaws.com",
        "rds.amazonaws.com"
      ]
    }
  }

  statement {
    sid    = "ProtectWorkloadBoundary"
    effect = "Deny"
    actions = [
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion"
    ]
    resources = [aws_iam_policy.workload_boundary.arn]
  }

  statement {
    sid    = "DenyTerraformRoleSelfModification"
    effect = "Deny"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:PutRolePolicy",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole"
    ]
    resources = [aws_iam_role.terraform_execution.arn]
  }
}

resource "aws_iam_role_policy" "terraform_iam_management" {
  name   = "doro-erp-dev-iam-management"
  role   = aws_iam_role.terraform_execution.id
  policy = data.aws_iam_policy_document.terraform_iam_management.json
}

# PowerUserAccess covers the non-IAM AWS resources in the Dev stack. IAM role
# creation remains constrained by the project-name, tag and boundary rules above.
resource "aws_iam_role_policy_attachment" "terraform_power_user" {
  role       = aws_iam_role.terraform_execution.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "terraform_service_linked_roles" {
  statement {
    sid     = "CreateRequiredServiceLinkedRoles"
    effect  = "Allow"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = [
      "arn:aws:iam::*:role/aws-service-role/eks.amazonaws.com/*",
      "arn:aws:iam::*:role/aws-service-role/elasticloadbalancing.amazonaws.com/*",
      "arn:aws:iam::*:role/aws-service-role/rds.amazonaws.com/*"
    ]
  }
}

resource "aws_iam_role_policy" "terraform_service_linked_roles" {
  name   = "doro-erp-dev-service-linked-roles"
  role   = aws_iam_role.terraform_execution.id
  policy = data.aws_iam_policy_document.terraform_service_linked_roles.json
}

data "aws_iam_openid_connect_provider" "github" {
  arn = var.github_oidc_provider_arn
}

data "aws_iam_policy_document" "github_assume_role" {
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
      values   = sort(tolist(var.github_ecr_subjects))
    }
  }
}

resource "aws_iam_role" "github_ecr_push" {
  name                 = local.github_ecr_role_name
  description          = "GitHub Actions role for pushing Doro ERP backend images to ECR."
  assume_role_policy   = data.aws_iam_policy_document.github_assume_role.json
  max_session_duration = 3600
  permissions_boundary = aws_iam_policy.workload_boundary.arn
}

data "aws_iam_policy_document" "github_ecr_push" {
  statement {
    sid       = "GetEcrAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushDoroImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/doro-erp-*"
    ]
  }
}

resource "aws_iam_role_policy" "github_ecr_push" {
  name   = "doro-erp-dev-ecr-push"
  role   = aws_iam_role.github_ecr_push.id
  policy = data.aws_iam_policy_document.github_ecr_push.json
}
