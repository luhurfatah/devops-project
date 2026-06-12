# ─── Staging AWS Load Balancer Controller ─────────────────────
# Provisions IAM role, Helm release, and Gateway API CRDs.
# Depends on the EKS stack being deployed first.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../../modules/aws/lb-controller"
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  mock_outputs = {
    cluster_id              = "eks-cluster-mock"
    cluster_oidc_issuer_url = "https://oidc.eks.us-east-1.amazonaws.com/id/FAKE"
    cluster_vpc_id          = "vpc-12345"
  }
}

inputs = {
  cluster_name                  = dependency.eks.outputs.cluster_id
  cluster_oidc_issuer_url       = dependency.eks.outputs.cluster_oidc_issuer_url
  cluster_vpc_id                = dependency.eks.outputs.cluster_vpc_id
  controller_namespace          = "kube-system"
  service_account_name          = "aws-load-balancer-controller"
  controller_chart_version      = "1.7.1"
  create_iam_policy             = true
  iam_policy_name               = "devops-project-stag-AWSLoadBalancerControllerPolicy"
  iam_role_name                 = "devops-project-stag-aws-load-balancer-controller-role"
  enable_shield                 = false
  enable_waf                    = false
  enable_wafv2                  = false
  install_gateway_api_crds      = true
  extra_helm_values             = {}
  tags                          = {}
}
