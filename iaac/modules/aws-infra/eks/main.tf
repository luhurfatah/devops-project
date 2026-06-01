data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# IAM Role for EKS Cluster
resource "aws_iam_role" "cluster" {
  name = "${var.name_prefix}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-eks-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "service_policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.cluster.name
}

# Note: AmazonEKSServicePolicy is deprecated but kept for backward compatibility.
# It has been superseded by AmazonEKSClusterPolicy (attached above).
# Consider removing this attachment for EKS clusters >= 1.35.
# IAM Role for Fargate Pod Execution
resource "aws_iam_role" "fargate" {
  name = "${var.name_prefix}-eks-fargate-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks-fargate-pods.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-eks-fargate-role"
  })
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate.name
}

# EKS Cluster
resource "aws_eks_cluster" "this" {
  name     = var.name_prefix
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  access_config {
    authentication_mode = "API"
  }

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = [var.eks_cluster_security_group_id]
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-eks-cluster"
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.service_policy,
  ]
}

# Fargate Profiles
resource "aws_eks_fargate_profile" "this" {
  for_each = var.fargate_profiles

  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "${var.name_prefix}-fargate-${each.key}"
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = var.private_subnet_ids

  dynamic "selector" {
    for_each = each.value.selectors
    content {
      namespace = selector.value.namespace
      labels    = selector.value.labels
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-fargate-${each.key}"
  })

  depends_on = [
    aws_iam_role_policy_attachment.fargate_pod_execution,
  ]
}

# EKS Addons
resource "aws_eks_addon" "this" {
  for_each = var.eks_addons

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value.addon_name
  addon_version               = each.value.addon_version
  resolve_conflicts_on_create = try(each.value.resolve_conflicts_on_create, "OVERWRITE")
  resolve_conflicts_on_update = try(each.value.resolve_conflicts_on_update, "OVERWRITE")

  configuration_values = try(each.value.configuration_values, null)

  depends_on = [
    aws_eks_fargate_profile.this,
  ]
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "node_group" {
  name = "${var.name_prefix}-eks-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-eks-node-group-role"
  })
}

resource "aws_iam_role_policy_attachment" "node_group_worker" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_cni" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_ecr" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

# EKS Managed Node Groups
resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name_prefix}-${each.key}"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
  }

  instance_types = each.value.instance_types
  capacity_type  = try(each.value.capacity_type, "ON_DEMAND")

  labels = try(each.value.labels, {})

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-${each.key}"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_group_worker,
    aws_iam_role_policy_attachment.node_group_cni,
    aws_iam_role_policy_attachment.node_group_ecr,
  ]
}

# OIDC Provider for IRSA
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-eks-oidc"
  })
}

locals {
  access_entry_arn = var.access_entry_username != null ? "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:user/${var.access_entry_username}" : var.access_entry_arn
}

resource "aws_eks_access_entry" "this" {
  count         = local.access_entry_arn != null ? 1 : 0
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = local.access_entry_arn
  type          = var.access_entry_type
  user_name     = var.access_entry_username
  tags          = merge(var.common_tags, {
    Name = "${var.name_prefix}-eks-access-entry"
  })
}

resource "aws_eks_access_policy_association" "this" {
  count                      = local.access_entry_arn != null ? 1 : 0
  cluster_name               = aws_eks_cluster.this.name
  principal_arn              = local.access_entry_arn
  policy_arn                 = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type       = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.this
  ]
}