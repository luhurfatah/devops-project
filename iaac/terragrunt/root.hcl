# Root Terragrunt configuration
# This file defines the remote state backend and provider configuration
# shared across all environments.
#
# Security: Checkov runs as a before_hook before every plan/apply.
# Install locally: pip install checkov
# Config: iaac/checkov.yaml (skips Terragrunt-generated file checks)

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket         = "devops-project-terraform-state-4ar0p0xb"
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
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "devops-project"
      ManagedBy   = "terragrunt"
    }
  }
}
EOF
}

# ---------------------------------------------------------------------------
# Security gate: Checkov static analysis
# Runs before every plan/apply. Non-zero exit blocks the operation.
# Uses checkov.yaml in the project root for skip-check configuration.
# ---------------------------------------------------------------------------
terraform {
  before_hook "checkov" {
    commands = ["plan", "apply"]
    execute = [
      "sh", "-c",
      "if command -v checkov > /dev/null 2>&1; then checkov -d . --config-file ${get_repo_root()}/iaac/checkov.yaml --framework terraform --quiet; else echo '[WARN] checkov not found, skipping scan. Install with: pip install checkov'; fi"
    ]
  }
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
  }
}
EOF
}