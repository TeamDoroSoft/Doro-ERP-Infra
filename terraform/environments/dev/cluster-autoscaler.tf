data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    sid    = "DescribeAutoscalingCapacity"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ScaleOnlyTaggedDoroNodeGroups"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/${local.name_prefix}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${local.name_prefix}-cluster-autoscaler"
  description = "Least-privilege capacity controls for the Dev EKS Cluster Autoscaler."
  policy      = data.aws_iam_policy_document.cluster_autoscaler.json
}

resource "aws_iam_role" "cluster_autoscaler" {
  name                 = "${local.name_prefix}-cluster-autoscaler"
  assume_role_policy   = data.aws_iam_policy_document.pod_identity_assume.json
  permissions_boundary = local.workload_boundary_arn
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

resource "aws_eks_pod_identity_association" "cluster_autoscaler" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "cluster-autoscaler"
  role_arn        = aws_iam_role.cluster_autoscaler.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.cluster_autoscaler
  ]
}
