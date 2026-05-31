# Dev environment configuration
locals {
  environment  = "dev"
  project_name = "devops-project"
  region       = "us-east-1"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Source the root module
terraform {
  source = "../../../modules/aws-infra"
}

inputs = {
  environment          = local.environment
  project_name         = local.project_name
  region               = local.region

  # VPC
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true

  # Security Groups
  allowed_ssh_cidrs    = ["0.0.0.0/0"]
  allowed_http_cidrs   = ["0.0.0.0/0"]
  allowed_https_cidrs  = ["0.0.0.0/0"]

  # EKS
  eks_cluster_version          = "1.30"
  eks_endpoint_private_access  = true
  eks_endpoint_public_access   = true
  eks_public_access_cidrs      = ["0.0.0.0/0"]

  # Fargate Profiles
  fargate_profiles = {
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
    applications = {
      selectors = {
        applications = {
          namespace = "applications"
        }
      }
    }
  }

  # Tags
  tags = {
    Environment = "dev"
    Project     = "myapp"
    ManagedBy   = "terragrunt"
  }
}