# Infrastructure as Code (IaC)

This directory contains the Terraform/Terragrunt infrastructure for deploying AWS resources including VPC, Security Groups, Network ACLs, Subnets, and EKS with Fargate.

## Directory Structure

```
iaac/
├── modules/
│   └── aws-infra/              # Root Terraform module
│       ├── main.tf             # Main module that orchestrates sub-modules
│       ├── variables.tf        # Root module variables
│       ├── outputs.tf          # Root module outputs
│       ├── versions.tf         # Provider and version requirements
│       ├── vpc/                # VPC sub-module
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── subnet/             # Subnet sub-module (public/private + NAT)
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── sg/                 # Security Group sub-module
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── acl/                # Network ACL sub-module
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── eks/                # EKS with Fargate sub-module
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
└── terragrunt/                 # Terragrunt configurations
    ├── terragrunt.hcl          # Root Terragrunt config (shared)
    └── env/
        ├── dev/                # Development environment
        │   └── terragrunt.hcl
        ├── stag/               # Staging environment
        │   └── terragrunt.hcl
        └── prod/               # Production environment
            └── terragrunt.hcl
```

## Module Architecture

The `aws-infra` module is composed of 5 sub-modules:

| Sub-Module | Description |
|------------|-------------|
| **vpc** | Creates VPC with DNS support, Internet Gateway |
| **subnet** | Creates public/private subnets across AZs, NAT Gateway(s) |
| **sg** | Security Groups for ALB, EKS cluster, and EKS nodes |
| **acl** | Network ACLs for public and private subnets |
| **eks** | EKS cluster with Fargate profiles, IAM roles, OIDC provider |

## Prerequisites

- Terraform >= 1.3.0
- Terragrunt >= 0.50.0
- AWS CLI configured with appropriate credentials
- S3 bucket for remote state (created manually or via bootstrap)

## Usage

### Initialize and apply a specific environment

```bash
# Development
cd iaac/terragrunt/env/dev
terragrunt init
terragrunt plan
terragrunt apply

# Staging
cd iaac/terragrunt/env/stag
terragrunt init
terragrunt plan
terragrunt apply

# Production
cd iaac/terragrunt/env/prod
terragrunt init
terragrunt plan
terragrunt apply
```

### Destroy infrastructure

```bash
cd iaac/terragrunt/env/dev
terragrunt destroy
```

## Environment Comparison

| Feature | dev | stag | prod |
|---------|-----|------|------|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 | 10.100.0.0/16 |
| Availability Zones | 2 | 3 | 3 |
| NAT Gateway | Single | One per AZ | One per AZ |
| EKS Endpoint | Public + Private | Public + Private | Private only |
| Fargate Profiles | 3 (kube-system, default, applications) | 4 (+ monitoring) | 5 (+ ingress) |

## Fargate Profiles

Fargate profiles define which Kubernetes namespaces and pods are run on AWS Fargate. Each environment has profiles for:

- **kube-system**: CoreDNS and other system components
- **default**: Default namespace workloads
- **applications**: Application workloads
- **monitoring** (stag/prod): Monitoring stack (Prometheus, Grafana, etc.)
- **ingress** (prod): Ingress controller pods

## Outputs

After applying, key outputs include:
- VPC ID and CIDR
- Public/Private subnet IDs
- Security Group IDs (ALB, EKS cluster, EKS nodes)
- EKS cluster endpoint, certificate, and OIDC issuer
- Fargate profile IDs and ARNs
- IAM role ARNs for cluster and Fargate execution