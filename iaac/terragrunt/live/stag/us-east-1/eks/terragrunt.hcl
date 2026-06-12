# ─── Staging EKS Stack ────────────────────────────────────────
# Provisions EKS cluster and AWS Load Balancer Controller.
# Depends on the VPC stack being deployed first.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../../modules/aws/eks-stack"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  mock_outputs = {
    vpc_id                     = "vpc-00000000"
    private_subnet_ids         = ["subnet-00000000", "subnet-00000001", "subnet-00000002"]
    eks_cluster_security_group_id = "sg-00000000"
  }
}

inputs = {
  environment          = "stag"
  project_name         = "devops-project"

  # ─── VPC Dependencies ─────────────────────────────────────────
  vpc_id                        = dependency.vpc.outputs.vpc_id
  private_subnet_ids            = dependency.vpc.outputs.private_subnet_ids
  eks_cluster_security_group_id = dependency.vpc.outputs.eks_cluster_security_group_id

  # ─── EKS ──────────────────────────────────────────────────────
  cluster_version               = "1.35"
  endpoint_private_access       = true
  endpoint_public_access        = true
  public_access_cidrs           = ["0.0.0.0/0"]

  # ─── IAM Access Entry ─────────────────────────────────────────
  access_entry_username         = "cloud_user"
  access_entry_type             = "STANDARD"

  # ─── EKS Addons ───────────────────────────────────────────────
  eks_addons = {
    coredns = {
      addon_name                  = "coredns"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      configuration_values = jsonencode({
        computeType = "Fargate"
      })
    }
  }

  # ─── Fargate Profiles ─────────────────────────────────────────
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

  # ─── AWS Load Balancer Controller ─────────────────────────────
  lb_controller_namespace              = "kube-system"
  lb_controller_service_account        = "aws-load-balancer-controller"
  lb_controller_chart_version          = "1.7.1"
  lb_controller_create_iam_policy      = true
  lb_controller_iam_policy_name        = "AWSLoadBalancerControllerPolicy"
  lb_controller_iam_role_name          = "aws-load-balancer-controller-role"
  lb_controller_enable_shield          = false
  lb_controller_enable_waf             = false
  lb_controller_enable_wafv2           = false
  lb_controller_install_gateway_api_crds = true
  lb_controller_extra_helm_values = {}
}