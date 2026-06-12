# ─── Dev VPC Stack ────────────────────────────────────────────
# Provisions VPC, subnets, security groups, and network ACLs.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../../modules/aws/vpc-stack"
}

inputs = {
  environment          = "dev"
  project_name         = "devops-project"

  # ─── VPC ──────────────────────────────────────────────────────
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true

  # ─── Security Groups ──────────────────────────────────────────
  allowed_ssh_cidrs    = ["0.0.0.0/0"]
  allowed_http_cidrs   = ["0.0.0.0/0"]
  allowed_https_cidrs  = ["0.0.0.0/0"]
}