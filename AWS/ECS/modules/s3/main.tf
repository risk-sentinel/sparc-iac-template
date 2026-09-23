locals {
  name_prefix = "${var.project_name}-${var.environment}"
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${local.name_prefix}-uploads"

  # ---------------------------------------------------------------------------
  # BYO uploads bucket (sparc-iac#310) — selector between the module-created
  # bucket and an externally-managed bucket discovered via data source.
  # ---------------------------------------------------------------------------
  uploads_bucket_id  = var.create_uploads_bucket ? aws_s3_bucket.uploads[0].id : data.aws_s3_bucket.uploads[0].id
  uploads_bucket_arn = var.create_uploads_bucket ? aws_s3_bucket.uploads[0].arn : data.aws_s3_bucket.uploads[0].arn
  uploads_bucket_rdn = var.create_uploads_bucket ? aws_s3_bucket.uploads[0].bucket_regional_domain_name : data.aws_s3_bucket.uploads[0].bucket_regional_domain_name
}

# ---------------------------------------------------------------------------
# S3 Bucket for SPARC ActiveStorage Uploads
# ---------------------------------------------------------------------------
# When create_uploads_bucket = false, this module discovers an existing
# bucket via the `data "aws_s3_bucket" "uploads"` block below instead.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "uploads" {
  # Design note (#611) — every control checkov flags on this resource IS
  # implemented, just in a sibling resource that its static analysis cannot
  # follow through the `count` guard added in #310:
  #
  #   CKV_AWS_18   access logging  -> aws_s3_bucket_logging.uploads (modules/logging)
  #   CKV_AWS_21   versioning      -> aws_s3_bucket_versioning.uploads (below)
  #   CKV_AWS_145  KMS-CMK at rest -> aws_s3_bucket_server_side_encryption_configuration.uploads (below)
  #   CKV2_AWS_6   public access   -> aws_s3_bucket_public_access_block.uploads (below)
  #   CKV2_AWS_61  lifecycle       -> aws_s3_bucket_lifecycle_configuration.uploads (below)
  #                                   (90-day noncurrent expiry + 7-day abort-incomplete-multipart)
  #
  # These were inline `checkov:skip` directives until #611. Inline skips make
  # checkov report SKIPPED, which removes the finding from checkov-baseline.yml
  # tracking entirely — no NIST mapping, no reviewer, no review cadence, no
  # POA&M line (docs/dev/issue_rules.md). The acceptances now live in the
  # baseline; the reasoning stays here with the code.
  count         = var.create_uploads_bucket ? 1 : 0
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = {
    Name = "${local.name_prefix}-uploads"
  }
}

data "aws_s3_bucket" "uploads" {
  count  = var.create_uploads_bucket ? 0 : 1
  bucket = var.existing_bucket_name
}

# ---------------------------------------------------------------------------
# Encryption (KMS-CMK server-side) — module-created bucket only
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  count  = var.create_uploads_bucket ? 1 : 0
  bucket = aws_s3_bucket.uploads[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# ---------------------------------------------------------------------------
# Versioning — module-created bucket only
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_versioning" "uploads" {
  count  = var.create_uploads_bucket ? 1 : 0
  bucket = aws_s3_bucket.uploads[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------------------------
# Block Public Access — module-created bucket only
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "uploads" {
  count  = var.create_uploads_bucket ? 1 : 0
  bucket = aws_s3_bucket.uploads[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# SSL-Only Bucket Policy — module-created bucket only
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "uploads" {
  count  = var.create_uploads_bucket ? 1 : 0
  bucket = aws_s3_bucket.uploads[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonSSLRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.uploads[0].arn,
          "${aws_s3_bucket.uploads[0].arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Lifecycle — expire noncurrent versions — module-created bucket only
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  count  = var.create_uploads_bucket ? 1 : 0
  bucket = aws_s3_bucket.uploads[0].id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------------------
# CORS (for ActiveStorage direct uploads) — module-created bucket only
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_cors_configuration" "uploads" {
  count  = var.create_uploads_bucket ? 1 : 0
  bucket = aws_s3_bucket.uploads[0].id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}
