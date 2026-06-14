# ─── Dev AWS Load Balancer Controller ─────────────────────────
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
    cluster_id                  = "eks-cluster-mock"
    cluster_endpoint            = "https://mock-eks-endpoint.us-east-1.eks.amazonaws.com"
    cluster_certificate_authority = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURDekNDQWZPZ0F3SUJBZ0lVV0ZKV0VKcVlWc2VUVEFRRkRTV2xxbmQzWHZjd0NnWUlLb1pJemowRUF3TXcKTVFzd0NRWURWUVFHRXdKVlV6RVFNQTRHQTFVRUNBd0hTR1ZzWjJsdU1SY3dGUVlEVlFRS0RBNXdkV0p6WVd4cApZWE41YzNSbGJIQXhGakFVQmdOVkJBTU1EV05oYzJsdVpIQjFibUZ0WlhNd0hoY05NakF3TlRBME1qQXlNVFUwCldoY05NekF3TlRBMU1qQXlNVFUwV2pBeExqQXNCZ05WQkFvTUpXNTBaVzUxWVM1amIyMHViV1Z0WldOMGJtOHUKYzJWeWRtbGpaWE11WVhCd2N5NWpiMjB3V1RBVEJnY3Foa2pPUFFJQkJnZ3Foa2pPUFFNQkJ3TkNBQVJvTgpjNVRTbTNsRjVKdkhmdFBJSUs5d3JhVUZPNkFhM3RrQkQ5YXRrUW5LQlNnWmVhSVkzS3RNdEVMcm5WZ25pCjZ1cnQ4VnBvclFkMnJYQUN1eTVXMW80SFlNSUhVTUE0R0ExVWREd0VCL3dRRUF3SUZvREFkQmdOVkhTVUUKRWpBUU1BZ0dCQ3VnT0NXd0dDZ3FiajRqUVFFRUF3SUZBakFNQmdOVkhSTUJBZjhFQWpBQU1CMEdBMVVkRGdRVwpCQlR5MXNhVmpFcGhvU2FvV09ZSkFSSjd3Ymt2bURDQm9RWURWUjBqQkhFd2JZQkZQTFd4cFdNU21HcEpxaFk1CmdrQkVudkJ1UytZb3BLa2pCek1GRXhDekFKQmdOVkJBWVRBbFZUTVJBd0RnWURWUVFJREFkSVpXeG5hVzR4CkZ6QVZCZ05WQkFvTURuQjFZbk5oYkdGamMzbHpkR1ZzY0RFV01CUUdBMVVFQXd3TlkyRnphVzVrY0hWdVlXMWwKY3pBcUJnTlZCQU1NSW1SMVpHOWpkQzVsWkdGdUxtTnNiM1ZrTFhKbGNYVmxjM1F1WTI5dE1Gc3dFUVlIS29aSQp6ajBDQVFZSUtvWkl6ajBEQVFjRFFnQUVhRFhPVTBwdDVSZVNieDd6enlDQ2ZjSzJsQlR1Z0d0N1pBUS9XclpFCkp5Z1VvR1htaUdOeXJUTFJDNjUxWUo0dXFyZkZhYUswSGRxMXdBcnN1VnRhT0h3PT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo="
    cluster_oidc_issuer_url    = "https://oidc.eks.us-east-1.amazonaws.com/id/FAKE"
    cluster_vpc_id             = "vpc-12345"
  }
}

inputs = {
  cluster_name                  = dependency.eks.outputs.cluster_id
  cluster_endpoint              = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority = dependency.eks.outputs.cluster_certificate_authority
  cluster_oidc_issuer_url       = dependency.eks.outputs.cluster_oidc_issuer_url
  cluster_vpc_id                = dependency.eks.outputs.cluster_vpc_id
  controller_namespace          = "kube-system"
  service_account_name          = "aws-load-balancer-controller"
  controller_chart_version      = "1.7.1"
  create_iam_policy             = true
  iam_policy_name               = "devops-project-dev-AWSLoadBalancerControllerPolicy"
  iam_role_name                 = "devops-project-dev-aws-load-balancer-controller-role"
  enable_shield                 = false
  enable_waf                    = false
  enable_wafv2                  = false
  install_gateway_api_crds      = true
  extra_helm_values             = {}
  tags                          = {}
}
