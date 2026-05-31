# Staging environment configuration
locals {
  environment  = "stag"
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

  # VPC - larger CIDR for staging
  vpc_cidr             = "10.1.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = false

  # Security Groups - restrict SSH to internal ranges
  allowed_ssh_cidrs    = ["10.0.0.0/8", "172.16.0.0/12"]
  allowed_http_cidrs   = ["0.0.0.0/0"]
  allowed_https_cidrs  = ["0.0.0.0/0"]

  # EKS
  eks_cluster_version          = "1.30"
  eks_endpoint_private_access  = true
  eks_endpoint_public_access   = true
  eks_public_access_cidrs      = ["10.0.0.0/8", "172.16.0.0/12"]

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
    monitoring = {
      selectors = {
        monitoring = {
          namespace = "monitoring"
        }
      }
    }
  }

  # Tags
  tags = {
    Environment = "stag"
    Project     = "devops-project"
    ManagedBy   = "terragrunt"
  }
}