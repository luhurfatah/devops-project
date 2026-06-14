# ─── EKS Stack Module ─────────────────────────────────────────
# Self-contained module provisioning EKS cluster and AWS Load Balancer Controller.
# Depends on a VPC stack being deployed first.

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge({
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }, var.tags)
}

# ─── IAM Role for EKS Cluster ──────────────────────────────────
resource "aws_iam_role" "eks_cluster" {
  name = "${local.name_prefix}-eks-cluster-role"

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

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# ─── IAM Role for Fargate Pod Execution ────────────────────────
resource "aws_iam_role" "fargate_pod" {
  name = "${local.name_prefix}-fargate-pod-role"

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

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate_pod.name
}

# ─── EKS Cluster ───────────────────────────────────────────────
resource "aws_eks_cluster" "this" {
  name     = "${local.name_prefix}-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = [var.eks_cluster_security_group_id]
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cluster"
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]
}

# ─── Fargate Profiles ──────────────────────────────────────────
resource "aws_eks_fargate_profile" "this" {
  for_each               = var.fargate_profiles
  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = each.key
  pod_execution_role_arn = aws_iam_role.fargate_pod.arn
  subnet_ids             = try(each.value.subnet_ids, var.private_subnet_ids)

  dynamic "selector" {
    for_each = each.value.selectors
    content {
      namespace = selector.value.namespace
      labels    = try(selector.value.labels, null)
    }
  }

  tags = merge(local.common_tags, try(each.value.tags, {}), {
    Name = "${local.name_prefix}-fargate-${each.key}"
  })

  depends_on = [
    aws_iam_role_policy_attachment.fargate_pod_execution,
  ]
}

# ─── Access Entries ────────────────────────────────────────────
resource "aws_eks_access_entry" "this" {
  count         = var.access_entry_arn != null && var.access_entry_arn != "" ? 1 : 0
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.access_entry_arn
  type          = var.access_entry_type
  user_name     = var.access_entry_username
}

resource "aws_eks_access_policy_association" "this" {
  count         = var.access_entry_arn != null && var.access_entry_arn != "" ? 1 : 0
  cluster_name  = aws_eks_cluster.this.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = var.access_entry_arn
  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.this,
  ]
}

# ─── EKS Add-ons ───────────────────────────────────────────────
resource "aws_eks_addon" "this" {
  for_each                    = { for a in var.eks_addons : a.addon_name => a }
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value.addon_name
  addon_version               = try(each.value.addon_version, null)
  configuration_values        = try(each.value.configuration_values, null)
  resolve_conflicts_on_create = try(each.value.resolve_conflicts_on_create, "OVERWRITE")
  resolve_conflicts_on_update = try(each.value.resolve_conflicts_on_update, "OVERWRITE")

  tags = local.common_tags

  depends_on = [
    aws_eks_fargate_profile.this,
  ]
}

# NOTE: AWS Load Balancer Controller is deployed as a separate
# terragrunt unit (lb-controller/) that depends on this eks-stack.
# See project/iaac/terragrunt/live/<env>//lb-controller/
