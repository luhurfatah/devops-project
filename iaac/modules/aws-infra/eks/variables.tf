variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS"
  type        = list(string)
}

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

variable "eks_cluster_security_group_id" {
  description = "Security group ID for the EKS cluster"
  type        = string
}

variable "access_entry_username" {
  description = "IAM username to grant EKS access (will construct ARN dynamically)"
  type        = string
  default     = null
}

variable "access_entry_arn" {
  description = "Full ARN of IAM principal (use this instead of access_entry_username for non-user principals)"
  type        = string
  default     = null
}

variable "access_entry_type" {
  description = "Type of the IAM principal: STANDARD, EC2_LINUX, EC2_WINDOWS"
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