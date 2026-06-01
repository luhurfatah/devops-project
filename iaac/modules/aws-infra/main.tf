locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge({
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }, var.tags)
}

# VPC Module
module "vpc" {
  source = "./vpc"

  vpc_cidr             = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
  name_prefix          = local.name_prefix
  common_tags          = local.common_tags
}

# Subnet Module
module "subnet" {
  source = "./subnet"

  vpc_id                = module.vpc.vpc_id
  internet_gateway_id   = module.vpc.internet_gateway_id
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  enable_nat_gateway    = var.enable_nat_gateway
  single_nat_gateway    = var.single_nat_gateway
  name_prefix           = local.name_prefix
  common_tags           = local.common_tags
}

# Security Group Module
module "sg" {
  source = "./sg"

  vpc_id              = module.vpc.vpc_id
  vpc_cidr            = module.vpc.vpc_cidr_block
  name_prefix         = local.name_prefix
  common_tags         = local.common_tags
  allowed_ssh_cidrs   = var.allowed_ssh_cidrs
  allowed_http_cidrs  = var.allowed_http_cidrs
  allowed_https_cidrs = var.allowed_https_cidrs
}

# Network ACL Module
module "acl" {
  source = "./acl"

  vpc_id              = module.vpc.vpc_id
  vpc_cidr            = module.vpc.vpc_cidr_block
  public_subnet_ids   = module.subnet.public_subnet_ids
  private_subnet_ids  = module.subnet.private_subnet_ids
  name_prefix         = local.name_prefix
  common_tags         = local.common_tags
}

# EKS Module
module "eks" {
  source = "./eks"

  environment                  = var.environment
  project_name                 = var.project_name
  name_prefix                  = local.name_prefix
  common_tags                  = local.common_tags
  vpc_id                       = module.vpc.vpc_id
  private_subnet_ids           = module.subnet.private_subnet_ids
  cluster_version              = var.eks_cluster_version
  endpoint_private_access      = var.eks_endpoint_private_access
  endpoint_public_access       = var.eks_endpoint_public_access
  public_access_cidrs          = var.eks_public_access_cidrs
  fargate_profiles             = var.fargate_profiles
  eks_cluster_security_group_id = module.sg.eks_cluster_sg_id
  access_entry_username        = var.access_entry_username
  access_entry_arn             = var.access_entry_arn
  access_entry_type            = var.access_entry_type
  eks_addons                   = var.eks_addons
  node_groups                  = var.node_groups
}