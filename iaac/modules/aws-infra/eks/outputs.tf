output "cluster_id" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "The ARN of the EKS cluster"
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster API server"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for EKS cluster"
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "The OIDC issuer URL for the EKS cluster"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "fargate_profile_ids" {
  description = "Map of Fargate profile IDs"
  value       = { for k, v in aws_eks_fargate_profile.this : k => v.id }
}

output "fargate_profile_arns" {
  description = "Map of Fargate profile ARNs"
  value       = { for k, v in aws_eks_fargate_profile.this : k => v.arn }
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC provider"
  value       = aws_iam_openid_connect_provider.this.arn
}

output "cluster_iam_role_arn" {
  description = "The ARN of the EKS cluster IAM role"
  value       = aws_iam_role.cluster.arn
}

output "fargate_iam_role_arn" {
  description = "The ARN of the Fargate execution IAM role"
  value       = aws_iam_role.fargate.arn
}