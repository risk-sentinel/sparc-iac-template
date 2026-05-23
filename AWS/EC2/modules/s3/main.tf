locals {
  name_prefix = "${var.project_name}-${var.environment}"
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${local.name_prefix}-uploads"
}

# ---------------------------------------------------------------------------
# S3 Bucket for SPARC ActiveStorage Uploads
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "uploads" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = {
    Name = "${local.name_prefix}-uploads"
  }
}

# ---------------------------------------------------------------------------
# Encryption (AES-256 server-side)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# ---------------------------------------------------------------------------
# Versioning
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------------------------
# Block Public Access
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# CORS (for ActiveStorage direct uploads)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}
