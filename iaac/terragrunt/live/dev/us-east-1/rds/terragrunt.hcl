# ─── Dev RDS Stack ────────────────────────────────────────────
# Provisions RDS PostgreSQL in private subnets.
# Depends on the VPC stack being deployed first.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../../modules/aws/rds-stack"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  mock_outputs = {
    vpc_id             = "vpc-00000000"
    vpc_cidr_block     = "10.0.0.0/16"
    private_subnet_ids = ["subnet-00000000", "subnet-00000001"]
  }
}

inputs = {
  environment  = "dev"
  project_name = "devops-project"

  # ─── VPC Dependencies ─────────────────────────────────────────
  vpc_id             = dependency.vpc.outputs.vpc_id
  vpc_cidr_block     = dependency.vpc.outputs.vpc_cidr_block
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids

  # ─── RDS Sizing (Dev) ────────────────────────────────────────
  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  multi_az                = false
  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = false
}
