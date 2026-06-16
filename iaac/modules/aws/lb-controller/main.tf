# ─── AWS Load Balancer Controller Terraform Module ─────────────
# Deploys the AWS Load Balancer Controller Helm chart on an EKS cluster
# with IRSA (IAM Roles for Service Accounts).
# Gateway API CRDs are deployed separately via the gateway-api-crds Helm chart.

terraform {
  required_version = ">= 1.0"
}

# ─── Data Sources ──────────────────────────────────────────────

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ─── Helm Provider ─────────────────────────────────────────────
# Configure the Helm provider to authenticate with the EKS cluster
# using aws eks get-token via the AWS CLI.
provider "helm" {
  kubernetes = {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_certificate_authority)
    exec                  = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    }
  }
}

# ─── IAM Policy ────────────────────────────────────────────────

data "http" "iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "lb_controller" {
  count = var.create_iam_policy ? 1 : 0

  name        = var.iam_policy_name
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = data.http.iam_policy.response_body
  tags        = var.tags
}

# ─── IAM Role ──────────────────────────────────────────────────

locals {
  oidc_provider = replace(var.cluster_oidc_issuer_url, "https://", "")
}

data "aws_iam_policy_document" "lb_controller_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:${var.controller_namespace}:${var.service_account_name}"]
    }

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider}"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = var.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = var.create_iam_policy ? aws_iam_policy.lb_controller[0].arn : var.existing_policy_arn
}

# ─── Helm Release ──────────────────────────────────────────────

locals {
  helm_set_values = concat(
    [
      {
        name  = "clusterName"
        value = var.cluster_name
      },
      {
        name  = "serviceAccount.create"
        value = "true"
      },
      {
        name  = "serviceAccount.name"
        value = var.service_account_name
      },
      {
        name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
        value = aws_iam_role.lb_controller.arn
      },
      {
        name  = "region"
        value = data.aws_region.current.name
      },
      {
        name  = "vpcId"
        value = var.cluster_vpc_id
      },
      {
        name  = "enableShield"
        value = tostring(var.enable_shield)
      },
      {
        name  = "enableWaf"
        value = tostring(var.enable_waf)
      },
      {
        name  = "enableWafv2"
        value = tostring(var.enable_wafv2)
      },
    ],
    var.enable_gateway_api ? [
      {
        name  = "controllerConfig.featureGates.ALBGatewayAPI"
        value = "true"
      },
      {
        name  = "controllerConfig.featureGates.NLBGatewayAPI"
        value = "true"
      },
    ] : [],
    [for k, v in var.extra_helm_values : {
      name  = k
      value = v
    }]
  )
}

resource "helm_release" "lb_controller" {
  name             = "aws-load-balancer-controller"
  namespace        = var.controller_namespace
  create_namespace = true
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  version          = var.controller_chart_version

  set = local.helm_set_values

  depends_on = [aws_iam_role_policy_attachment.lb_controller]
}

