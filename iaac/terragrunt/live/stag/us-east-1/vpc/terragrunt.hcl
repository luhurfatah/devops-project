# ─── Staging VPC Stack ────────────────────────────────────────
# Provisions VPC, subnets, security groups, and network ACLs.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../../modules/aws/vpc-stack"
}

inputs = {
  environment          = "stag"
  project_name         = "devops-project"

  # ─── VPC ──────────────────────────────────────────────────────
  vpc_cidr             = "10.1.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = false

  # ─── Security Groups ──────────────────────────────────────────
  allowed_ssh_cidrs    = ["10.0.0.0/8", "172.16.0.0/12"]
  allowed_http_cidrs   = ["0.0.0.0/0"]
  allowed_https_cidrs  = ["0.0.0.0/0"]
}