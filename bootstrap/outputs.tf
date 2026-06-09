# ── State backend ────────────────────────────────────────────────────────────
output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "Name of the Terragrunt state S3 bucket"
}

output "state_bucket_arn" {
  value       = aws_s3_bucket.terraform_state.arn
  description = "ARN of the Terragrunt state S3 bucket"
}

# ── GitHub OIDC ──────────────────────────────────────────────────────────────
output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.github.arn
  description = "ARN of the GitHub OIDC provider"
}

output "plan_role_arn" {
  value       = aws_iam_role.github_plan.arn
  description = "role-to-assume in pr-plan.yml (read-only)"
}

output "apply_role_arn" {
  value       = aws_iam_role.github_apply.arn
  description = "role-to-assume in merge-apply.yml (admin, main only)"
}
