# ─── AWS Load Balancer Controller Module Variables ─────────────

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "controller_namespace" {
  description = "Kubernetes namespace for the AWS Load Balancer Controller"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account for the controller"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "controller_chart_version" {
  description = "Version of the AWS Load Balancer Controller Helm chart"
  type        = string
  default     = "3.0.0"
}

variable "create_iam_policy" {
  description = "Whether to create the IAM policy for the controller"
  type        = bool
  default     = true
}

variable "iam_policy_name" {
  description = "Name of the IAM policy for the controller"
  type        = string
  default     = "AWSLoadBalancerControllerPolicy"
}

variable "existing_policy_arn" {
  description = "ARN of an existing IAM policy to attach (when create_iam_policy is false)"
  type        = string
  default     = ""
}

variable "iam_role_name" {
  description = "Name of the IAM role for the controller"
  type        = string
  default     = "aws-load-balancer-controller-role"
}

variable "enable_shield" {
  description = "Enable AWS Shield Advanced"
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Enable AWS WAF Classic"
  type        = bool
  default     = false
}

variable "enable_wafv2" {
  description = "Enable AWS WAF v2"
  type        = bool
  default     = false
}

variable "enable_gateway_api" {
  description = "Enable Gateway API support (ALBGatewayAPI and NLBGatewayAPI feature gates)"
  type        = bool
  default     = true
}


variable "extra_helm_values" {
  description = "Additional Helm values for the AWS Load Balancer Controller"
  type        = map(string)
  default     = {}
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster (from eks-stack output)"
  type        = string
}

variable "cluster_vpc_id" {
  description = "VPC ID where the EKS cluster is deployed (from eks-stack output)"
  type        = string
}

variable "cluster_endpoint" {
  description = "The endpoint URL for the EKS cluster API server (from eks-stack output)"
  type        = string
}

variable "cluster_certificate_authority" {
  description = "The base64-encoded certificate authority data for the EKS cluster (from eks-stack output)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
