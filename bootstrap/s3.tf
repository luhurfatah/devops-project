# ─── State Backend ─────────────────────────────────────────────
# S3 Bucket for Terraform Remote State.
# Uses S3 native locking (use_lockfile = true in Terragrunt root.hcl).
# No DynamoDB table is needed.
# ────────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "terraform_state" {
  bucket        = "terragrunt-state-170928836252-us-east-1"
  force_destroy = true

  tags = {
    Name      = "terragrunt-state-170928836252-us-east-1"
    ManagedBy = "Terraform"
    Purpose   = "Terragrunt remote state"
  }
}

resource "aws_s3_bucket_versioning" "enabled" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_encryption" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state_block" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}