# ─── AWS Load Balancer Controller Module Outputs ──────────────

output "controller_role_arn" {
  description = "ARN of the IAM role for the AWS Load Balancer Controller"
  value       = aws_iam_role.lb_controller.arn
}

output "controller_service_account" {
  description = "Name of the Kubernetes service account for the controller"
  value       = var.service_account_name
}

output "controller_namespace" {
  description = "Namespace where the controller is deployed"
  value       = var.controller_namespace
}