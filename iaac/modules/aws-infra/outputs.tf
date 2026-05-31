output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.subnet.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.subnet.private_subnet_ids
}

output "public_subnet_cidrs" {
  description = "List of public subnet CIDRs"
  value       = module.subnet.public_subnet_cidrs
}

output "private_subnet_cidrs" {
  description = "List of private subnet CIDRs"
  value       = module.subnet.private_subnet_cidrs
}

output "nat_gateway_ips" {
  description = "List of NAT Gateway public IPs"
  value       = module.subnet.nat_gateway_ips
}

output "eks_cluster_id" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_id
}

output "eks_cluster_arn" {
  description = "The ARN of the EKS cluster"
  value       = module.eks.cluster_arn
}

output "eks_cluster_endpoint" {
  description = "The endpoint for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for EKS cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "eks_cluster_oidc_issuer_url" {
  description = "The OIDC issuer URL for the EKS cluster"
  value       = module.eks.cluster_oidc_issuer_url
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.sg.eks_cluster_sg_id
}

output "alb_security_group_id" {
  description = "Security group ID for the ALB"
  value       = module.sg.alb_sg_id
}

output "fargate_profile_ids" {
  description = "Map of Fargate profile IDs"
  value       = module.eks.fargate_profile_ids
}