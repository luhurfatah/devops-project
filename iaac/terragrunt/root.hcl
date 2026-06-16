# ─── Root Terragrunt Configuration ─────────────────────────────
# This file defines the remote state backend and provider configuration
# shared across all environments.
#
# Security: Checkov runs as a before_hook before every plan/apply.
# Install locally: pip install checkov
# Config: iaac/checkov.yaml (skips Terragrunt-generated file checks)

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.account_id
  aws_region   = local.region_vars.locals.aws_region
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket         = "terragrunt-state-170928836252-us-east-1"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    use_lockfile   = true
  }
}
EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  allowed_account_ids = ["${local.account_id}"]

  default_tags {
    tags = {
      Project     = "devops-project"
      ManagedBy   = "terragrunt"
      Environment = "${local.account_name}"
    }
  }
}
EOF
}

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
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0.0"
    }
  }
}
EOF
}

# The helm and kubernetes providers are configured dynamically in each
# terragrunt unit via a local provider_helm.tf file, since they depend
# on EKS cluster data sources that are created within the same module.