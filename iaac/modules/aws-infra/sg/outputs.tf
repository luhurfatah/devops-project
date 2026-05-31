output "alb_sg_id" {
  description = "The ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "eks_cluster_sg_id" {
  description = "The ID of the EKS cluster security group"
  value       = aws_security_group.eks_cluster.id
}

output "eks_nodes_sg_id" {
  description = "The ID of the EKS nodes security group"
  value       = aws_security_group.eks_nodes.id
}

output "alb_sg_arn" {
  description = "The ARN of the ALB security group"
  value       = aws_security_group.alb.arn
}

output "eks_cluster_sg_arn" {
  description = "The ARN of the EKS cluster security group"
  value       = aws_security_group.eks_cluster.arn
}