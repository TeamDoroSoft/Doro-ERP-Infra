resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.name_prefix}/cluster"
  retention_in_days = 7
}

resource "aws_eks_cluster" "this" {
  name     = local.name_prefix
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.35"

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  kubernetes_network_config {
    service_ipv4_cidr = "172.20.0.0/16"
  }

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.eks_public_access_cidrs
    subnet_ids = [
      data.aws_subnet.app_a.id,
      data.aws_subnet.app_c.id
    ]
  }

  depends_on = [
    aws_cloudwatch_log_group.eks,
    aws_iam_role_policy_attachment.eks_cluster,
    terraform_data.network_contract
  ]
}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.eks_admin_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.admin.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_launch_template" "eks_node" {
  name_prefix            = "${local.name_prefix}-alpha-"
  description            = "Doro ERP Prod Alpha EKS worker nodes with mandatory team tags."
  update_default_version = true

  block_device_mappings {
    device_name = "/prod/xvda"

    ebs {
      delete_on_termination = true
      encrypted             = true
      volume_size           = 50
      volume_type           = "gp3"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_protocol_ipv6          = "disabled"
    http_put_response_hop_limit = 2
    http_tokens                 = "required"
    instance_metadata_tags      = "enabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  tags = {
    Name = "${local.name_prefix}-alpha-node-template"
  }
}

resource "aws_eks_node_group" "alpha" {
  cluster_name           = aws_eks_cluster.this.name
  node_group_name_prefix = "${local.name_prefix}-alpha-"
  node_role_arn          = aws_iam_role.eks_node.arn
  # Prod workloads intentionally stay in AZ-a. The EKS control plane and ALB
  # continue to use both application subnets, but worker capacity scales only
  # inside the lower-cost single-AZ development failure domain.
  subnet_ids = [data.aws_subnet.app_a.id]

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = ["t3.large"]

  launch_template {
    id      = aws_launch_template.eks_node.id
    version = aws_launch_template.eks_node.latest_version
  }

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    environment = "prod"
    cell        = "alpha"
  }

  # Required for aws_iam_role.cluster_autoscaler's tag-scoped IAM condition
  # to authorize scaling actions on this node group's underlying ASG.
  tags = {
    "k8s.io/cluster-autoscaler/enabled"              = "true"
    "k8s.io/cluster-autoscaler/${local.name_prefix}" = "owned"
  }

  lifecycle {
    create_before_destroy = true

    # Cluster Autoscaler owns desired capacity after the initial two-node
    # foundation has been created. Terraform continues to own the bounds.
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    terraform_data.network_contract,
    aws_iam_role_policy_attachment.eks_node,
    aws_iam_role_policy.session_logs["eks-node"],
    aws_eks_addon.vpc_cni
  ]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "vpc-cni"
  addon_version = data.aws_eks_addon_version.vpc_cni.version

  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_node_group.alpha]
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "metrics-server"
  addon_version = data.aws_eks_addon_version.metrics_server.version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_node_group.alpha]
}

resource "aws_eks_addon" "secrets_store_csi" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "aws-secrets-store-csi-driver-provider"
  addon_version = "v3.1.2-eksbuild.1"

  configuration_values = jsonencode({
    awsRegion = var.aws_region
    secrets-store-csi-driver = {
      syncSecret = {
        enabled = true
      }
      enableSecretRotation = true
      rotationPollInterval = "2m"
    }
  })

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    terraform_data.network_contract
  ]
}

resource "aws_eks_pod_identity_association" "workload" {
  for_each = local.app_names

  cluster_name    = aws_eks_cluster.this.name
  namespace       = "doro-alpha"
  service_account = "${each.key}-api"
  role_arn        = aws_iam_role.workload[each.key].arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_eks_addon.secrets_store_csi
  ]
}

resource "aws_eks_pod_identity_association" "migration" {
  for_each = local.migration_app_names

  cluster_name    = aws_eks_cluster.this.name
  namespace       = "doro-alpha"
  service_account = "${each.key}-migration"
  role_arn        = aws_iam_role.migration[each.key].arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_eks_addon.secrets_store_csi
  ]
}
