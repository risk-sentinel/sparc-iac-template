# ===========================================================================
# Bootstrap — Terraform State Infrastructure
# ===========================================================================
# Creates the S3 bucket, DynamoDB lock table, and KMS key used by all
# other Terraform configurations for remote state.
#
# New deployment setup:
#   1. cd bootstrap && terraform init    (local state on first run)
#   2. terraform apply -var="aws_region=us-east-1"
#   3. Copy the backend_config output into the backend block below
#   4. terraform init -migrate-state     (moves local → S3)
#   5. Update backend blocks in AWS/ECS/main.tf, AWS/EC2/main.tf, etc.
#
# See bootstrap/README.md for the full walkthrough.
# ===========================================================================

terraform {
  # Partial backend config — values supplied at init via:
  #   terraform init -backend-config=backend.hcl
  # See backend.example.hcl for the template.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  bucket_name = "sparc-${var.environment}-tf-state-${random_id.suffix.hex}"
  table_name  = "sparc-${var.environment}-tf-locks"
  key_alias   = "alias/sparc-${var.environment}-tf-state"
}

# ---------------------------------------------------------------------------
# KMS Key for State Encryption
# ---------------------------------------------------------------------------

resource "aws_kms_key" "state" {
  description             = "Encrypts SPARC Terraform state files"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name    = "sparc-${var.environment}-tf-state-key"
    Purpose = "terraform-state"
  }
}

resource "aws_kms_alias" "state" {
  name          = local.key_alias
  target_key_id = aws_kms_key.state.key_id
}

# ---------------------------------------------------------------------------
# S3 Bucket for State Files
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  tags = {
    Name    = local.bucket_name
    Purpose = "terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ---------------------------------------------------------------------------
# DynamoDB Table for State Locking
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "locks" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state.arn
  }

  tags = {
    Name    = local.table_name
    Purpose = "terraform-state-lock"
  }
}
