# ─── GitHub OIDC ───────────────────────────────────────────────
# Lets GitHub Actions authenticate to AWS via OIDC (no static keys).
#
# Two roles, least-privilege by trigger:
#   - GitHubActionPlanRole  — read-only, assumable from PRs   (pr-plan.yml)
#   - GitHubActionApplyRole — admin,     assumable from main  (merge-apply.yml)
# So untrusted PR code can only ever read, never apply.
# ────────────────────────────────────────────────────────────────

# ─── Thumbprint ─────────────────────────────────────────────────
# Fetched dynamically. AWS ignores it for the well-known GitHub IdP
# (validated against a trusted CA since 2023), but this keeps it from going
# stale and documents intent — no hardcoded fingerprint to rot.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = {
    Name      = "github-actions-oidc"
    ManagedBy = "Terraform"
  }
}

# ─── Plan Role — READ-ONLY ─────────────────────────────────────
# Assumable from pull requests (and manual dispatch on main).
# Cannot create/modify/destroy infrastructure.
# ────────────────────────────────────────────────────────────────
resource "aws_iam_role" "github_plan" {
  name = "GitHubActionPlanRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRoleWithWebIdentity"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo::pull_request",
              "repo::ref:refs/heads/main",
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name      = "GitHubActionPlanRole"
    ManagedBy = "Terraform"
    Purpose   = "GitHub Actions OIDC terragrunt plan"
  }
}

# ─── Plan Read Access ───────────────────────────────────────────
# Broad read across services so `terragrunt plan` can refresh state.
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.github_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ─── State Lock Access ──────────────────────────────────────────
# ReadOnlyAccess already grants s3:GetObject/ListBucket on the state bucket;
# plan additionally needs to write/remove the S3 native lock object.
resource "aws_iam_role_policy" "plan_state_lock" {
  name = "terraform-state-lock"
  role = aws_iam_role.github_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ManageStateLock"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.terraform_state.arn}/*.tflock"
      }
    ]
  })
}

# ─── Apply Role — ADMIN ────────────────────────────────────────
# Assumable only from the main branch (push or dispatch),
# so a malicious PR can never reach it.
# ────────────────────────────────────────────────────────────────
resource "aws_iam_role" "github_apply" {
  name = "GitHubActionApplyRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRoleWithWebIdentity"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo::ref:refs/heads/main",
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name      = "GitHubActionApplyRole"
    ManagedBy = "Terraform"
    Purpose   = "GitHub Actions OIDC terragrunt apply"
  }
}

# ─── Admin Apply Access ─────────────────────────────────────────
# Admin so the pipeline can create any resource. Scoped to main-branch trust
# above, so only post-merge applies can use it.
resource "aws_iam_role_policy_attachment" "apply_admin" {
  role       = aws_iam_role.github_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}