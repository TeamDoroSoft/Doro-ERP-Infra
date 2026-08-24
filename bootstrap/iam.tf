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
  description = "Permissions boundary for Doro ERP prod workload and service roles."
  policy      = data.aws_iam_policy_document.workload_boundary.json
}

data "aws_iam_policy_document" "terraform_assume_role" {
  statement {
    sid     = "AllowApprovedTerraformOperators"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = sort(tolist(local.terraform_operator_principal_arns))
    }

    condition {
      test     = "StringLike"
      variable = "sts:RoleSessionName"
      values   = ["doro-erp-prod-*"]
    }
  }
}

resource "aws_iam_role" "terraform_execution" {
  name                 = local.terraform_role_name
  description          = "Terraform execution role for the Doro ERP prod environment."
  assume_role_policy   = data.aws_iam_policy_document.terraform_assume_role.json
  max_session_duration = 3600
}

resource "aws_iam_group" "terraform_operators" {
  name = "doro-erp-prod-terraform-operators"
}

resource "aws_iam_group_membership" "terraform_operators" {
  name  = "doro-erp-prod-terraform-operators-membership"
  group = aws_iam_group.terraform_operators.name
  users = sort(tolist(var.terraform_operator_user_names))
}

data "aws_iam_policy_document" "terraform_operator_assume" {
  statement {
    sid       = "AssumeDoroErpProdTerraformRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.terraform_execution.arn]
  }
}

resource "aws_iam_policy" "terraform_operator_assume" {
  name        = "doro-erp-prod-terraform-assume"
  description = "Allows approved Doro ERP Prod operators to assume the Terraform execution role."
  policy      = data.aws_iam_policy_document.terraform_operator_assume.json
}

resource "aws_iam_group_policy_attachment" "terraform_operator_assume" {
  group      = aws_iam_group.terraform_operators.name
  policy_arn = aws_iam_policy.terraform_operator_assume.arn
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
      "iam:GetGroup",
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

  # Bootstrap owns the operator group, its membership, the Prod SSM policy and
  # the attachment. IAM users themselves remain account prerequisites.
  statement {
    sid    = "ManageProdSsmAccessPolicy"
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
    resources = [local.prod_ssm_access_policy_arn]
  }

  statement {
    sid    = "AttachProdSsmAccessPolicy"
    effect = "Allow"
    actions = [
      "iam:AttachGroupPolicy",
      "iam:DetachGroupPolicy",
      "iam:ListAttachedGroupPolicies"
    ]
    resources = [aws_iam_group.team2_operators.arn]
  }

  # doro-erp-service-ecr-publisher is the canonical GitHub Actions role for
  # publishing Doro ERP service images to ECR (Doro-ERP-Service's prod
  # Environment variable AWS_ECR_PUSH_ROLE_ARN points at it). It replaces
  # the never-used doro-erp-prod-github-ecr-push, which has been removed.
  statement {
    sid    = "ManageDoroErpServiceEcrPublisher"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreateRole",
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
      "iam:CreatePolicy",
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
  name   = "doro-erp-prod-iam-management"
  role   = aws_iam_role.terraform_execution.id
  policy = data.aws_iam_policy_document.terraform_iam_management.json
}

# PowerUserAccess covers the non-IAM AWS resources in the Prod stack. IAM role
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
      "arn:aws:iam::*:role/aws-service-role/eks-nodegroup.amazonaws.com/*",
      "arn:aws:iam::*:role/aws-service-role/elasticloadbalancing.amazonaws.com/*",
      "arn:aws:iam::*:role/aws-service-role/rds.amazonaws.com/*",
      "arn:aws:iam::*:role/aws-service-role/elasticache.amazonaws.com/*",
      "arn:aws:iam::*:role/aws-service-role/autoscaling.amazonaws.com/*",
      "arn:aws:iam::*:role/aws-service-role/vpcorigin.cloudfront.amazonaws.com/*"
    ]
  }

  statement {
    sid       = "ConfigureElastiCacheServiceLinkedRole"
    effect    = "Allow"
    actions   = ["iam:PutRolePolicy"]
    resources = ["arn:aws:iam::*:role/aws-service-role/elasticache.amazonaws.com/AWSServiceRoleForElastiCache*"]
  }
}

resource "aws_iam_role_policy" "terraform_service_linked_roles" {
  name   = "doro-erp-prod-service-linked-roles"
  role   = aws_iam_role.terraform_execution.id
  policy = data.aws_iam_policy_document.terraform_service_linked_roles.json
}

data "aws_iam_openid_connect_provider" "github" {
  arn = var.github_oidc_provider_arn
}
