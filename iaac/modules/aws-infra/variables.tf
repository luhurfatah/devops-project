variable "environment" {
  description = "Environment name (dev, stag, prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "myapp"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all private subnets"
  type        = bool
  default     = false
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in VPC"
  type        = bool
  default     = true
}

# Security Group variables
variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_http_cidrs" {
  description = "CIDR blocks allowed for HTTP access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_https_cidrs" {
  description = "CIDR blocks allowed for HTTPS access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# EKS variables
variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.30"
}

variable "eks_endpoint_private_access" {
  description = "Enable private access to EKS API endpoint"
  type        = bool
  default     = true
}

variable "eks_endpoint_public_access" {
  description = "Enable public access to EKS API endpoint"
  type        = bool
  default     = true
}

variable "eks_public_access_cidrs" {
  description = "CIDR blocks allowed to access EKS public endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Fargate variables
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
  default = {
    kube-system = {
      selectors = {
        kube-system = {
          namespace = "kube-system"
          labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }
    }
    default = {
      selectors = {
        default = {
          namespace = "default"
        }
      }
    }
  }
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
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