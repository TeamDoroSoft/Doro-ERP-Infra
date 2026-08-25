data "aws_iam_policy_document" "eks_cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name                 = "${local.name_prefix}-eks-cluster"
  assume_role_policy   = data.aws_iam_policy_document.eks_cluster_assume.json
  permissions_boundary = local.workload_boundary_arn
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name                 = "${local.name_prefix}-eks-node"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume.json
  permissions_boundary = local.workload_boundary_arn
}

resource "aws_iam_role_policy_attachment" "eks_node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ])

  role       = aws_iam_role.eks_node.name
  policy_arn = each.value
}

resource "aws_iam_role" "management_instance" {
  name                 = "${local.name_prefix}-management"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume.json
  permissions_boundary = local.workload_boundary_arn
}

resource "aws_iam_role_policy_attachment" "management_ssm" {
  role       = aws_iam_role.management_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "management" {
  name = "${local.name_prefix}-management"
  role = aws_iam_role.management_instance.name
}

# Incident-response convenience grant (deliberate exception to least
# privilege): full EKS control-plane access, but scoped to doro-erp-prod
# only — never to other teams' clusters in this shared account. A separate
# statement covers the handful of EKS actions AWS does not support
# resource-level permissions for (list/catalog-style calls); those are
# unavoidably account-wide but read-only.
data "aws_iam_policy_document" "management_eks_admin" {
  statement {
    sid    = "ManageDoroEksClusterAndSubresources"
    effect = "Allow"
    actions = [
      "eks:*"
    ]
    resources = [
      aws_eks_cluster.this.arn,
      "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:*/${aws_eks_cluster.this.name}/*"
    ]
  }

  statement {
    sid    = "ReadEksAccountCatalog"
    effect = "Allow"
    actions = [
      "eks:ListClusters",
      "eks:ListUpdates",
      "eks:DescribeAddonVersions"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "management_eks_admin" {
  name   = "DoroERPProdEKSAdminPolicy"
  role   = aws_iam_role.management_instance.name
  policy = data.aws_iam_policy_document.management_eks_admin.json
}

# Same rationale as above, scoped to the six doro-erp-* repositories only.
data "aws_iam_policy_document" "management_ecr_admin" {
  statement {
    sid       = "EcrAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ManageDoroErpRepositories"
    effect = "Allow"
    actions = [
      "ecr:*"
    ]
    resources = [
      for app in local.app_names :
      "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/doro-erp-${app}"
    ]
  }
}

resource "aws_iam_role_policy" "management_ecr_admin" {
  name   = "DoroErpEcrAdminPolicy"
  role   = aws_iam_role.management_instance.name
  policy = data.aws_iam_policy_document.management_ecr_admin.json
}

data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "workload" {
  for_each = local.app_names

  name                 = "${local.name_prefix}-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.pod_identity_assume.json
  permissions_boundary = local.workload_boundary_arn
}

resource "aws_iam_role" "provider_admin_edge" {
  name                 = "${local.name_prefix}-provider-admin-edge"
  assume_role_policy   = data.aws_iam_policy_document.pod_identity_assume.json
  permissions_boundary = local.workload_boundary_arn
}

resource "aws_iam_role" "migration" {
  for_each = local.migration_app_names

  name                 = "${local.name_prefix}-${each.key}-migration"
  assume_role_policy   = data.aws_iam_policy_document.pod_identity_assume.json
  permissions_boundary = local.workload_boundary_arn
}
