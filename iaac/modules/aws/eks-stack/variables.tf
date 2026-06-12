variable "environment" {
  description = "Environment name (dev, stag, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

# ─── VPC Dependencies ──────────────────────────────────────────
variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS"
  type        = list(string)
}

variable "eks_cluster_security_group_id" {
  description = "Security group ID for the EKS cluster"
  type        = string
}

# ─── EKS Variables ─────────────────────────────────────────────
variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.35"
}

variable "endpoint_private_access" {
  description = "Enable private access to EKS API endpoint"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable public access to EKS API endpoint"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access EKS public endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "fargate_profiles" {
  description = "Map of Fargate profile configurations"
  type = map(object({
    selectors = map(object({
      namespace = string
      labels    = optional(map(string))
    }))
    subnet_ids = optional(list(string))
    tags       = optional(map(string))
  }))
  default = {}
}

variable "access_entry_username" {
  description = "IAM username to grant EKS access"
  type        = string
  default     = null
}

variable "access_entry_arn" {
  description = "Full ARN of IAM principal for EKS access"
  type        = string
  default     = null
}

variable "access_entry_type" {
  description = "Type of IAM principal: STANDARD, EC2_LINUX, EC2_WINDOWS"
  type        = string
  default     = "STANDARD"
}

variable "eks_addons" {
  description = "Map of EKS addon configurations"
  type = map(object({
    addon_name          = string
    addon_version       = optional(string)
    configuration_values = optional(string)
    resolve_conflicts_on_create = optional(string)
    resolve_conflicts_on_update = optional(string)
  }))
  default = {}
}

variable "node_groups" {
  description = "Map of EKS managed node group configurations"
  type = map(object({
    desired_size   = number
    max_size       = number
    min_size       = number
    instance_types = list(string)
    capacity_type  = optional(string)
    labels         = optional(map(string))
  }))
  default = {}
}

# ─── AWS Load Balancer Controller Variables ────────────────────
variable "lb_controller_namespace" {
  description = "Kubernetes namespace for the AWS Load Balancer Controller"
  type        = string
  default     = "kube-system"
}

variable "lb_controller_service_account" {
  description = "Name of the Kubernetes service account for the controller"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "lb_controller_chart_version" {
  description = "Version of the AWS Load Balancer Controller Helm chart"
  type        = string
  default     = "1.7.1"
}

variable "lb_controller_create_iam_policy" {
  description = "Whether to create the IAM policy for the controller"
  type        = bool
  default     = true
}

variable "lb_controller_iam_policy_name" {
  description = "Base name of the IAM policy for the controller"
  type        = string
  default     = "AWSLoadBalancerControllerPolicy"
}

variable "lb_controller_iam_role_name" {
  description = "Base name of the IAM role for the controller"
  type        = string
  default     = "aws-load-balancer-controller-role"
}

variable "lb_controller_enable_shield" {
  description = "Enable AWS Shield Advanced"
  type        = bool
  default     = false
}

variable "lb_controller_enable_waf" {
  description = "Enable AWS WAF Classic"
  type        = bool
  default     = false
}

variable "lb_controller_enable_wafv2" {
  description = "Enable AWS WAF v2"
  type        = bool
  default     = false
}

variable "lb_controller_install_gateway_api_crds" {
  description = "Whether to install Gateway API CRDs"
  type        = bool
  default     = true
}

variable "lb_controller_extra_helm_values" {
  description = "Additional Helm values for the AWS Load Balancer Controller"
  type        = map(string)
  default     = {}
}