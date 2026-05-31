# Root Terragrunt configuration
# This file defines the remote state backend and provider configuration
# shared across all environments.

# Read environment-specific configuration
locals {
  env_vars = read_terragrunt_config("${path_relative_to_include()}/env.hcl")
  environment  = local.env_vars.locals.environment
  project_name = local.env_vars.locals.project_name
  region       = local.env_vars.locals.region
}

# Generate remote state backend configuration with S3 locking
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket         = "${local.project_name}-terraform-state"
    key            = "${local.project_name}/${local.environment}/terraform.tfstate"
    region         = local.region
    encrypt        = true
    use_lockfile   = true
  }
}
EOF
}

# Generate provider configuration for all child modules
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = local.region

  default_tags {
    tags = {
      Environment = local.environment
      Project     = local.project_name
      ManagedBy   = "terragrunt"
    }
  }
}
EOF
}

# Generate versions file
generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}
EOF
}
