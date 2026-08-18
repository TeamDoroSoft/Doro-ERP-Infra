resource "aws_iam_policy" "load_balancer_controller" {
  name        = "${local.name_prefix}-aws-load-balancer-controller"
  description = "AWS API permissions for the Dev EKS AWS Load Balancer Controller v3.5.0."
  policy      = file("${path.module}/policies/aws-load-balancer-controller-v3.5.0.json")
}

resource "aws_iam_role" "load_balancer_controller" {
  name                 = "${local.name_prefix}-aws-load-balancer-controller"
  assume_role_policy   = data.aws_iam_policy_document.pod_identity_assume.json
  permissions_boundary = local.workload_boundary_arn
}

resource "aws_iam_role_policy_attachment" "load_balancer_controller" {
  role       = aws_iam_role.load_balancer_controller.name
  policy_arn = aws_iam_policy.load_balancer_controller.arn
}

resource "aws_eks_pod_identity_association" "load_balancer_controller" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.load_balancer_controller.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.load_balancer_controller
  ]
}
