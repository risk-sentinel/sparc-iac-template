locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "main" {}

# ---------------------------------------------------------------------------
# Security Artifacts S3 Bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "artifacts" {
  bucket = "${local.name_prefix}-security-artifacts"

  tags = {
    Name    = "${local.name_prefix}-security-artifacts"
    Purpose = "security-logs"
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"
    filter {}

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------------------
# Bucket Policy — allow ALB to write access logs
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid       = "DenyNonSSLRequests"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:*"
          Resource = [
            aws_s3_bucket.artifacts.arn,
            "${aws_s3_bucket.artifacts.arn}/*"
          ]
          Condition = {
            Bool = {
              "aws:SecureTransport" = "false"
            }
          }
        },
        {
          Sid    = "AllowALBAccessLogs"
          Effect = "Allow"
          Principal = {
            AWS = data.aws_elb_service_account.main.arn
          }
          Action   = "s3:PutObject"
          Resource = "${aws_s3_bucket.artifacts.arn}/alb-logs/*"
        },
        {
          Sid    = "AllowALBLogDelivery"
          Effect = "Allow"
          Principal = {
            Service = "delivery.logs.amazonaws.com"
          }
          Action   = "s3:PutObject"
          Resource = "${aws_s3_bucket.artifacts.arn}/alb-logs/*"
          Condition = {
            StringEquals = {
              "s3:x-amz-acl" = "bucket-owner-full-control"
            }
          }
        },
        {
          Sid    = "AllowALBLogDeliveryAclCheck"
          Effect = "Allow"
          Principal = {
            Service = "delivery.logs.amazonaws.com"
          }
          Action   = "s3:GetBucketAcl"
          Resource = aws_s3_bucket.artifacts.arn
        },
        {
          Sid    = "AllowS3AccessLogging"
          Effect = "Allow"
          Principal = {
            Service = "logging.s3.amazonaws.com"
          }
          Action   = "s3:PutObject"
          Resource = "${aws_s3_bucket.artifacts.arn}/s3-access-logs/*"
          Condition = {
            ArnLike = {
              "aws:SourceArn" = "arn:aws:s3:::${local.name_prefix}-uploads"
            }
          }
        },
        {
          Sid    = "AllowCloudTrailAclCheck"
          Effect = "Allow"
          Principal = {
            Service = "cloudtrail.amazonaws.com"
          }
          Action   = "s3:GetBucketAcl"
          Resource = aws_s3_bucket.artifacts.arn
        },
      ],
      [
        {
          Sid    = "AllowCloudTrailWrite"
          Effect = "Allow"
          Principal = {
            Service = "cloudtrail.amazonaws.com"
          }
          Action   = "s3:PutObject"
          Resource = "${aws_s3_bucket.artifacts.arn}/cloudtrail/*"
          Condition = {
            StringEquals = {
              "s3:x-amz-acl" = "bucket-owner-full-control"
            }
          }
        },
      ],
    )
  })
}

# ---------------------------------------------------------------------------
# S3 Access Logging on uploads bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_logging" "uploads" {
  bucket = var.uploads_bucket_id

  target_bucket = aws_s3_bucket.artifacts.id
  target_prefix = "s3-access-logs/"
}
