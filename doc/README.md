# KMS Platform Project

> **A full-stack Kubernetes platform on AWS EKS with Gateway API, Terragrunt IaC, and GitHub Actions CI/CD**

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Directory Structure](#directory-structure)
3. [Infrastructure (IaC)](#infrastructure-iac)
   - [Architecture](#architecture)
   - [Environments](#environments)
   - [Terraform Modules](#terraform-modules)
4. [Kubernetes (K8s)](#kubernetes-k8s)
   - [Helm Chart: kms-app](#helm-chart-kms-app)
   - [Gateway API Integration](#gateway-api-integration)
   - [Environment Overrides](#environment-overrides)
5. [Applications](#applications)
   - [API (Go)](#api-go)
   - [Web (Node.js)](#web-nodejs)
   - [Local Development](#local-development)
6. [CI/CD Pipelines](#cicd-pipelines)
7. [Getting Started](#getting-started)
   - [Prerequisites](#prerequisites)
   - [Bootstrap AWS Account](#bootstrap-aws-account)
   - [Deploy Infrastructure](#deploy-infrastructure)
   - [Deploy Application](#deploy-application)
8. [Configuration Guide](#configuration-guide)
   - [configure.sh](#configuresh)
   - [Environment Variables](#environment-variables)
9. [Security](#security)
   - [IAM Roles](#iam-roles)
   - [Secrets Management](#secrets-management)
   - [Checkov Scans](#checkov-scans)
10. [Operations](#operations)
    - [Monitoring](#monitoring)
    - [Troubleshooting](#troubleshooting)
    - [Cleanup](#cleanup)

---

## Project Overview

This project provisions a complete **Kubernetes-based platform on AWS** using:

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Infrastructure** | Terraform + Terragrunt | VPC, EKS, IAM, networking |
| **Orchestration** | Kubernetes (EKS with Fargate) | Container scheduling |
| **Networking** | Gateway API + AWS ALB | Ingress traffic management |
| **Application** | Go API + Node.js Web | Backend + frontend services |
| **CI/CD** | GitHub Actions | Automated plan/apply/destroy |
| **Security** | Checkov | IaC security scanning |

### Key Features

- **Multi-environment** (dev, staging, production) with isolated AWS accounts
- **Serverless Kubernetes** via EKS Fargate profiles (no node management)
- **Gateway API** for ALB provisioning (modern alternative to Ingress)
- **GitOps-ready** with Terragrunt dependency management
- **OIDC-based CI/CD** — no static AWS credentials in GitHub
- **Security scanning** integrated into the pipeline

---

## Directory Structure

```
project/
├── bootstrap/                          # Bootstrap Terraform (state bucket, OIDC)
│   ├── oidc.tf                         # GitHub OIDC provider + IAM roles
│   ├── s3.tf                           # S3 bucket for remote state
│   ├── providers.tf                    # AWS provider config
│   ├── outputs.tf                      # Bucket ARN, role ARNs
│   └── versions.tf                     # Provider version constraints
│
├── iaac/                               # Infrastructure as Code
│   ├── checkov.yaml                    # Security scan config
│   ├── README.md                       # IaC-specific documentation
│   ├── modules/aws/                    # Reusable Terraform modules (stack-based)
│   │   ├── vpc-stack/                  # VPC + subnets + NAT + ACLs + SGs
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── eks-stack/                  # EKS cluster + Fargate profiles
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── lb-controller/              # AWS Load Balancer Controller
│   │       ├── main.tf                 # IAM role, Helm release, Gateway API CRDs
│   │       ├── variables.tf
│   │       └── outputs.tf
│   └── terragrunt/                     # Terragrunt configurations
│       ├── root.hcl                    # Root config (remote state, providers)
│       └── live/
│           ├── dev/                    # Development environment
│           │   ├── account.hcl         # Account ID, profile
│           │   └── /
│           │       ├── region.hcl      # Region config
│           │       ├── vpc/terragrunt.hcl
│           │       ├── eks/terragrunt.hcl
│           │       └── lb-controller/terragrunt.hcl
│           ├── stag/                   # Staging environment
│           │   └── ... (same structure)
│           └── prod/                   # Production environment
│               └── ... (same structure)
│
├── k8s/                                # Kubernetes manifests
│   ├── charts/
│   │   ├── gateway-api-crds/           # Chart: Gateway API CRDs (OCI dep)
│   │   │   ├── Chart.yaml              # Dep: envoyproxy/gateway-crds-helm
│   │   │   ├── values.yaml             # CRDs only, envoyGateway disabled
│   │   │   └── templates/
│   │   │       └── _helpers.tpl
│   │   ├── gateway-api-resources/      # Chart: GatewayClass, Gateway, HTTPRoute
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml             # ALB annotations, listeners, routes
│   │   │   └── templates/
│   │   │       ├── _helpers.tpl
│   │   │       ├── gatewayclass.yaml
│   │   │       ├── gateway.yaml
│   │   │       └── httproute.yaml
│   │   └── kms-app/                    # Chart: Pure application (no infra)
│   │       ├── Chart.yaml
│   │       ├── values.yaml             # App config only
│   │       └── templates/
│   │           ├── _helpers.tpl
│   │           ├── api-deployment.yaml
│   │           ├── configmap.yaml
│   │           └── secret.yaml
│   └── environments/
│       ├── dev/values.yaml
│       ├── staging/values.yaml
│       └── prod/values.yaml
│
├── apps/                               # Application source code
│   ├── api/                            # Go API backend
│   │   ├── main.go
│   │   ├── Dockerfile
│   │   ├── go.mod / go.sum
│   │   ├── internal/
│   │   │   ├── api/                    # HTTP handlers
│   │   │   ├── auth/                   # Authentication
│   │   │   ├── config/                 # Configuration
│   │   │   ├── models/                 # Data models
│   │   │   └── store/                  # Database layer
│   │   └── migrations/                 # SQL migrations
│   ├── web/                            # Node.js web frontend
│   │   ├── server.js                   # Express server
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   └── public/                     # Static assets (HTML, CSS, JS)
│   ├── docker-compose.yml              # Local development
│   ├── .env.example                    # Environment variable template
│   └── README.md
│
├── .github/workflows/                  # CI/CD pipelines
│   ├── apps-api-ci.yml                 # API: build, scan, push to GHCR
│   ├── apps-web-ci.yml                 # Web: build, scan, push to GHCR
│   ├── tf-dev.yml                      # Dev IaC: plan/apply/destroy
│   ├── tf-stag.yml                     # Staging IaC: plan/apply/destroy
│   └── tf-prod.yml                     # Prod IaC: plan/apply/destroy
│
├── configure.sh                        # Repoint repo at new AWS account
├── doc/                                # Documentation
│   └── README.md                       # This file
└── .gitignore
```

---

## Infrastructure (IaC)

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AWS Account                                  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  VPC (10.0.0.0/16 dev, 10.1.0.0/16 stag, 10.2.0.0/16 prod) │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐  │   │
│  │  │ Public Subnets│  │Private Subnets│  │  NAT Gateway(s)   │  │   │
│  │  │ (ALB, NAT GW) │  │  (EKS Fargate)│  │  (1 or per-AZ)    │  │   │
│  │  └──────────────┘  └──────────────┘  └────────────────────┘  │   │
│  │                                                               │   │
│  │  ┌────────────────────────────────────────────────────────┐   │   │
│  │  │  EKS Cluster (Fargate-only)                            │   │   │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │   │   │
│  │  │  │ kube-system  │  │  default     │  │ applications │ │   │   │
│  │  │  │ (CoreDNS)    │  │ (app pods)   │  │ (monitoring)  │ │   │   │
│  │  │  └──────────────┘  └──────────────┘  └──────────────┘ │   │   │
│  │  └────────────────────────────────────────────────────────┘   │   │
│  │                                                               │   │
│  │  ┌────────────────────────────────────────────────────────┐   │   │
│  │  │  AWS Load Balancer Controller                          │   │   │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │   │   │
│  │  │  │ GatewayClass │  │   Gateway    │  │  HTTPRoute   │ │   │   │
│  │  │  │   aws-alb    │  │ kms-gateway  │  │ web + api    │ │   │   │
│  │  │  └──────────────┘  └──────────────┘  └──────────────┘ │   │   │
│  │  └────────────────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  S3 State Bucket (terraform-state-<ACCOUNT_ID>)              │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  GitHub OIDC Provider                                        │   │
│  │  ┌──────────────────────┐  ┌──────────────────────────────┐  │   │
│  │  │ GitHubActionPlanRole │  │ GitHubActionApplyRole        │  │   │
│  │  │ (ReadOnly, PRs)      │  │ (AdministratorAccess, main)  │  │   │
│  │  └──────────────────────┘  └──────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### Environments

| Feature | dev | stag | prod |
|---------|-----|------|------|
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` | `10.2.0.0/16` |
| Availability Zones | 2 | 3 | 3 |
| NAT Gateway | Single | One per AZ | One per AZ |
| EKS Endpoint | Public + Private | Public + Private | Private only |
| Fargate Profiles | 3 (kube-system, default, applications) | 4 (+ monitoring) | 5 (+ ingress) |
| Trigger | Manual (workflow_dispatch) | Manual | Manual |

### Terraform Modules

#### vpc-stack

Creates the networking foundation:

- **VPC** with DNS support and Internet Gateway
- **Public subnets** across AZs (for ALB, NAT Gateway)
- **Private subnets** across AZs (for EKS Fargate pods)
- **NAT Gateway** (single for dev, one per AZ for stag/prod)
- **Security Groups** for ALB, EKS cluster, and EKS Fargate
- **Network ACLs** for public and private subnets

#### eks-stack

Creates the Kubernetes cluster:

- **EKS cluster** with Fargate-only compute
- **Fargate profiles** for kube-system, default, applications (and monitoring/ingress in stag/prod)
- **IAM roles** for cluster and Fargate execution
- **OIDC provider** for IRSA (IAM Roles for Service Accounts)

#### lb-controller

Installs and configures the AWS Load Balancer Controller:

- **IAM policy** for the controller (downloaded from official source)
- **IAM role** with OIDC trust for the controller's service account
- **Helm release** of `aws-load-balancer-controller` from EKS charts
- Configurable WAF/Shield support

Note: Gateway API CRDs are deployed separately via the `gateway-api-crds` Helm chart (not Terraform).

---

## Kubernetes (K8s)

### Architecture

The K8s layer is split into three independent Helm charts, each with a single responsibility:

```
┌─────────────────────────────────────────────────────────────────┐
│  Deploy Order                                                    │
│                                                                  │
│  1. gateway-api-crds      Install Gateway API CRDs (once)       │
│          │                                                       │
│          ▼                                                       │
│  2. gateway-api-resources  Create GatewayClass, Gateway, Routes  │
│          │                                                       │
│          ▼                                                       │
│  3. kms-app                Deploy API + web workloads            │
└─────────────────────────────────────────────────────────────────┘
```

### Helm Chart: gateway-api-crds

Installs the Gateway API CRDs into the cluster using the Envoy Gateway CRDs OCI chart — no controller, just the CRDs.

```bash
# Install (run once per cluster)
helm upgrade --install gateway-api-crds ./k8s/charts/gateway-api-crds \
  --namespace gateway-api-crds \
  --create-namespace
```

**Chart details:**
| Field | Value |
|-------|-------|
| OCI dependency | `oci://docker.io/envoyproxy/gateway-crds-helm` |
| CRD channel | `standard` (Gateway API v1) |
| Envoy Gateway CRDs | Disabled |

### Helm Chart: gateway-api-resources

Creates the GatewayClass, Gateway, and HTTPRoute resources that provision the AWS ALB and define routing rules.

```bash
# Install (re-deploy when routes or ALB config change)
helm upgrade --install gateway-api-resources ./k8s/charts/gateway-api-resources \
  --namespace default \
  --values ./k8s/environments/dev/values.yaml
```

#### Gateway API Resource Flow

```
GatewayClass (cluster-scoped)
    │  controllerName: gateway.k8s.aws/load-balancer-controller
    ▼
Gateway (namespace-scoped)
    │  Provisions an AWS ALB
    │  Listener: HTTP :80
    ▼
HTTPRoute (namespace-scoped)
    │  Routes traffic to backend Services
    │  Hostname/path matching, traffic splitting
    ▼
Service → Pods (Deployments)
```

#### Templates

| Template | Resource | Purpose |
|----------|----------|---------|
| `gatewayclass.yaml` | GatewayClass | Defines the ALB controller implementation |
| `gateway.yaml` | Gateway | Represents the ALB instance with listeners |
| `httproute.yaml` | HTTPRoute | Routing rules for web and API services |

#### Key Gateway Annotations

| Annotation | Description | Values |
|-----------|-------------|--------|
| `alb.ingress.kubernetes.io/scheme` | ALB accessibility | `internet-facing`, `internal` |
| `alb.ingress.kubernetes.io/ip-address-type` | IP addressing | `ipv4`, `dualstack` |
| `alb.ingress.kubernetes.io/target-type` | Target registration | `ip` (pod IP) |
| `alb.ingress.kubernetes.io/healthcheck-path` | Health check endpoint | `/` |
| `alb.ingress.kubernetes.io/certificate-arn` | ACM certificate ARN | For HTTPS termination |

### Helm Chart: kms-app

Pure application chart — deploys the API and web workloads with ConfigMap and Secret. No infrastructure dependencies.

```bash
# Install
helm upgrade --install kms-app ./k8s/charts/kms-app \
  --namespace default \
  --values ./k8s/environments/dev/values.yaml
```

#### Templates

| Template | Resource | Description |
|----------|----------|-------------|
| `api-deployment.yaml` | Deployment + Service | Go API backend (port 8080) |
| `configmap.yaml` | ConfigMap | Application configuration |
| `secret.yaml` | Secret | Sensitive data (base64-encoded) |

### Environment Overrides

Environment-specific `values.yaml` files override the chart defaults:

| Environment | File | Key Differences |
|-------------|------|-----------------|
| **dev** | `environments/dev/values.yaml` | Single replica, debug logging |
| **staging** | `environments/staging/values.yaml` | 2 replicas, moderate resources |
| **prod** | `environments/prod/values.yaml` | 3+ replicas, HPA, production TLS |

---

## Applications

### API (Go)

The backend API is written in Go and provides RESTful endpoints for the KMS application.

```
apps/api/
├── main.go                    # Entry point, server bootstrap
├── Dockerfile                 # Multi-stage build
├── go.mod / go.sum            # Go module dependencies
├── internal/
│   ├── api/api.go             # HTTP handlers and routing
│   ├── auth/auth.go           # Authentication middleware
│   ├── config/config.go       # Environment-based configuration
│   ├── models/models.go       # Data models and validation
│   └── store/
│       ├── store.go           # Database interface
│       ├── migrate.go         # Schema migrations
│       ├── seed.go            # Seed data
│       └── slug.go            # URL slug generation
└── migrations/
    └── 0001_init.sql          # Initial database schema
```

**Port**: 8080 (container) → 8080 (service)

### Web (Node.js)

The frontend is a Node.js Express application serving static assets.

```
apps/web/
├── server.js                  # Express server
├── Dockerfile                 # Container definition
├── package.json               # Dependencies
└── public/
    ├── index.html             # Main HTML page
    ├── style.css              # Styling
    └── app.js                 # Client-side logic
```

**Port**: 3000 (container) → 3000 (service)

### Local Development

Run the full stack locally with Docker Compose:

```bash
cd apps
docker compose up --build
```

This starts:
- **API** at `http://localhost:8080`
- **Web** at `http://localhost:3000`

---

## CI/CD Pipelines

GitHub Actions workflows are defined in `.github/workflows/`:

| Workflow | Purpose | Trigger | Permissions |
|----------|---------|---------|-------------|
| `apps-api-ci.yml` | Build, scan, and push API image to GHCR | `workflow_dispatch` | Read + Write |
| `apps-web-ci.yml` | Build, scan, and push Web image to GHCR | `workflow_dispatch` | Read + Write |
| `tf-dev.yml` | Dev IaC: plan/apply/destroy | `workflow_dispatch` | Read + Write |
| `tf-stag.yml` | Staging IaC: plan/apply/destroy | `workflow_dispatch` | Read + Write |
| `tf-prod.yml` | Prod IaC: plan/apply/destroy | `workflow_dispatch` | Read + Write |

### Pipeline Stages

Each IaC workflow (`tf-*.yml`) runs two jobs:

1. **security-scan** — Checkov IaC security scan
   - Runs `terragrunt plan` and converts to JSON
   - Scans the plan with Checkov using `iaac/checkov.yaml` configuration
   - Fails the pipeline if critical/high-severity issues are found

2. **deploy** — Terragrunt plan/apply/destroy
   - Uses OIDC-based AWS credentials (no static keys)
   - Caches Terragrunt binary for faster subsequent runs
   - Runs `terragrunt run-all` across all modules in the environment

Each application CI workflow (`apps-*-ci.yml`) runs:

1. **build-and-scan** — Build Docker image, run container scan, push to GHCR
   - Uses OIDC-based AWS credentials for ECR (if needed)
   - Pushes tagged images to GitHub Container Registry

### OIDC Authentication

The workflows use GitHub's OIDC provider to assume IAM roles in AWS:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::<ACCOUNT_ID>:role/github-actions-role
    aws-region: <REGION>
```

Two IAM roles are created during bootstrap:
- **github-actions-role** — Used by workflows for plan/apply/destroy

---

## Getting Started

### Prerequisites

- **AWS Account** with administrative access
- **AWS CLI** configured locally
- **Terraform** >= 1.3.0
- **Terragrunt** >= 0.50.0
- **kubectl** (for interacting with EKS)
- **Helm v3** (for chart operations)
- **GitHub repository** with GitHub Actions enabled

### Bootstrap AWS Account

The `bootstrap/` directory contains Terraform to set up the foundational AWS resources:

```bash
cd bootstrap

# Initialize and apply
terraform init
terraform plan
terraform apply
```

This creates:
- **S3 bucket** for Terraform remote state (`terraform-state-<ACCOUNT_ID>`)
- **DynamoDB table** for state locking (`terraform-state-lock`)
- **GitHub OIDC provider** for CI/CD authentication
- **IAM roles** for GitHub Actions workflows

### Deploy Infrastructure

After bootstrapping, deploy the infrastructure with Terragrunt:

```bash
# Development environment
cd iaac/terragrunt/live/dev/

# Deploy in dependency order: vpc → eks → lb-controller
cd vpc && terragrunt apply
cd ../eks && terragrunt apply
cd ../lb-controller && terragrunt apply

# Or deploy all at once
terragrunt run-all apply
```

### Deploy Application

Once the EKS cluster is running and the LB controller is deployed via Terraform, install the Helm charts in order:

```bash
# Configure kubectl for the EKS cluster
aws eks update-kubeconfig --name devops-project-dev-cluster --region us-east-1

# Step 1: Install Gateway API CRDs (once per cluster)
# First, build the OCI dependency
cd k8s/charts/gateway-api-crds && helm dependency build && cd -
# Then install
helm upgrade --install gateway-api-crds ./k8s/charts/gateway-api-crds \
  --namespace gateway-api-crds \
  --create-namespace

# Step 2: Deploy Gateway API resources (GatewayClass, Gateway, HTTPRoutes)
helm upgrade --install gateway-api-resources ./k8s/charts/gateway-api-resources \
  --namespace default \
  --values ./k8s/environments/dev/values.yaml

# Step 3: Deploy the application
helm upgrade --install kms-app ./k8s/charts/kms-app \
  --namespace default \
  --values ./k8s/environments/dev/values.yaml
```

Verify the deployment:

```bash
# Check pods
kubectl get pods -l app=kms

# Check Gateway status (ALB provisioning — may take a few minutes)
kubectl get gateway kms-gateway

# Get ALB DNS name
kubectl get gateway kms-gateway -o jsonpath='{.status.addresses[0].value}'
```

---

## Configuration Guide

### configure.sh

The `configure.sh` script at the project root is used to repoint the repository to a new AWS account. This is useful when:

- Forking the repository for a new project
- Deploying to a different AWS account
- Setting up a new environment

```bash
./configure.sh --account-id 170928836252 --region <REGION>
```

The script updates:
- Terragrunt `account.hcl` files with the new account ID
- GitHub Actions workflow OIDC role ARNs
- Bootstrap Terraform variables

### Environment Variables

Key environment variables used across the project:

| Variable | Description | Source |
|----------|-------------|--------|
| `AWS_ACCOUNT_ID` | AWS account number | Terragrunt account.hcl |
| `AWS_REGION` | AWS region | Terragrunt region.hcl |
| `CLUSTER_NAME` | EKS cluster name | Terragrunt eks inputs |
| `VPC_ID` | VPC identifier | Terragrunt vpc outputs |
| `SUBNET_IDS` | Public/private subnet IDs | Terragrunt vpc outputs |
| `ACM_CERT_ARN` | ACM certificate for HTTPS | Terragrunt lb-controller inputs |

---

## Security

### IAM Roles

The project uses a least-privilege IAM model:

| Role | Trust Entity | Permissions | Used By |
|------|-------------|-------------|---------|
| `github-actions-role` | GitHub OIDC | Full access to deploy infrastructure | CI/CD pipelines |
| `EKSClusterRole` | EKS service | EKS management | EKS cluster |
| `EKSFargatePodExecutionRole` | EKS Fargate | Pull images, write logs | Fargate pods |
| `aws-load-balancer-controller` | Kubernetes SA (IRSA) | Create/manage ALBs, target groups | LB Controller pod |

### Secrets Management

- **Kubernetes Secrets** are stored in `k8s/charts/kms-app/templates/secret.yaml` as base64-encoded values
- **IAM roles** use OIDC trust — no long-term AWS credentials are stored in GitHub
- **Terraform state** is encrypted at rest in S3 (AES-256) and in transit (TLS)

### Checkov Scans

The `iaac/checkov.yaml` configuration defines security policies for IaC scanning:

```yaml
# Key checks enforced:
# - CKV_AWS_*: AWS resource security best practices
# - CKV2_AWS_*: AWS resource relationships
# - Ensure S3 buckets have encryption enabled
# - Ensure EKS clusters have logging enabled
# - Ensure security groups don't allow unrestricted ingress
```

To run Checkov locally:

```bash
cd iaac/terragrunt/live/dev/
terragrunt plan -out=tfplan
terraform show -json tfplan > plan.json
checkov -f plan.json --config-file $PWD/../../../../checkov.yaml
```

---

## Operations

### Monitoring

The EKS cluster is configured with:

- **CloudWatch Container Insights** — Metrics and logs for EKS
- **AWS CloudTrail** — API activity logging
- **ALB Access Logs** — HTTP request logging (when enabled)
- **Fargate logging** — Pod logs streamed to CloudWatch Logs

Key metrics to monitor:

| Metric | Source | Alert Threshold |
|--------|--------|-----------------|
| ALB 5xx errors | CloudWatch ALB metrics | > 1% of requests |
| Target response time | CloudWatch ALB metrics | > 5s p99 |
| Fargate CPU utilization | CloudWatch EKS metrics | > 80% |
| Fargate memory utilization | CloudWatch EKS metrics | > 80% |

### Troubleshooting

#### ALB Not Provisioning

```bash
# Check Gateway status
kubectl describe gateway kms-gateway

# Check Load Balancer Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50
```

**Common causes:**
- Missing subnet tags (`kubernetes.io/cluster/<name>`, `kubernetes.io/role/elb`)
- IAM permissions missing for the Load Balancer Controller
- VPC ID mismatch in controller configuration

#### Pods Not Starting

```bash
# Check pod status
kubectl get pods -l app=kms
kubectl describe pod <pod-name>

# Check Fargate profile configuration
aws eks describe-fargate-profile --cluster-name kms-dev --fargate-profile-name applications
```

**Common causes:**
- Fargate profile doesn't match pod namespace/labels
- Insufficient vCPU/memory limits for the pod
- IAM role for Fargate execution missing ECR permissions

#### HTTPRoute Not Accepted

```bash
kubectl describe httproute kms-web-route
```

**Common causes:**
- Backend service name or port doesn't match
- Gateway name in `parentRefs` is incorrect
- No matching listener on the Gateway (port/protocol mismatch)

### Cleanup

#### Destroy Application

```bash
helm uninstall kms-app -n default
helm uninstall gateway-api-resources -n default
helm uninstall gateway-api-crds -n gateway-api-crds
```

#### Destroy Infrastructure

```bash
cd iaac/terragrunt/live/dev/
terragrunt run-all destroy
```

#### Destroy Bootstrap Resources

```bash
cd bootstrap
terraform destroy
```

**Note**: Destroy order matters. Always destroy the application first, then infrastructure (reverse dependency order: lb-controller → eks → vpc), and finally bootstrap resources.

---

## Summary

This project provides a complete, production-ready platform on AWS EKS with:

| Component | Status | Notes |
|-----------|--------|-------|
| **Networking** | ✅ VPC with public/private subnets | Multi-AZ, NAT Gateway |
| **Compute** | ✅ EKS with Fargate | Serverless, no node management |
| **Ingress** | ✅ Gateway API + ALB | Modern alternative to Ingress |
| **CI/CD** | ✅ GitHub Actions with OIDC | No static credentials |
| **Security** | ✅ Checkov scanning | Integrated into pipeline |
| **Applications** | ✅ Go API + Node.js Web | Containerized, Docker Compose ready |

### Reference Resources

- [Kubernetes Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [EKS User Guide - Gateway API](https://docs.aws.amazon.com/eks/latest/userguide/gateway-api.html)
- [Terragrunt Documentation](https://terragrunt.gruntwork.io/docs/)
- [Checkov IaC Scanning](https://www.checkov.io/)
- [GitHub OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
