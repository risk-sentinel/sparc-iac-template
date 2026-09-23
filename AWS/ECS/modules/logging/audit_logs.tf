# ---------------------------------------------------------------------------
# Audit Logs S3 Bucket (#484) — AU-9 audit-immutable sink
#
# Segregates the tamper-sensitive, service-written audit logs (CloudTrail,
# AWS Config, ALB access logs, S3 server access logs) from the CI-writable
# evidence bucket (`${name_prefix}-security-artifacts`). Only AWS log-delivery
# services can write here; a bucket policy denies object delete/overwrite to
# every principal (WORM — AU-9). Deny-delete is a *policy* control, so it does
# NOT block S3 lifecycle expiration (an internal S3 action, not a principal
# request) — the 365-day retention still auto-purges. This gives GOVERNANCE-
# equivalent immutability WITHOUT bucket-wide object-lock default retention,
# which would fight the log writers (see the artifacts bucket note re #336).
#
# Encryption matches the artifacts bucket exactly (aws:kms + bucket_key) — that
# config is already proven-compatible with all four log writers on the current
# shared bucket, so delivery keeps working after the repoint.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "audit_logs" {
  bucket = "${local.name_prefix}-audit-logs"

  tags = {
    Name    = "${local.name_prefix}-audit-logs"
    Purpose = "audit-immutable-logs"
  }
}

resource "aws_s3_bucket_versioning" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  versioning_configuration {
    status = "Enabled"
  }

  # The bucket policy is the only thing that could deny s3:PutBucketVersioning
  # to the CI role; apply it first so a stale deny (e.g. the #503 partial apply)
  # is lifted before this PutBucketVersioning call runs.
  depends_on = [aws_s3_bucket_policy.audit_logs]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 1-year retention (#484). CBA (issue thread) showed cold-storage tiering is
# ~16x MORE expensive here — the audit stream is hundreds of thousands of tiny
# objects, so per-object transition requests + min-object-size overhead dwarf
# any storage saving. Straight Standard + 365d expiration is both cheaper and
# simpler. Lifecycle expiration is unaffected by the deny-delete policy below.
resource "aws_s3_bucket_lifecycle_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    id     = "expire-audit-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = 365
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
# Bucket Policy — WORM deny-delete + allow the four log-delivery services
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonSSLRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.audit_logs.arn,
          "${aws_s3_bucket.audit_logs.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      # WORM (#484, AU-9): no principal may delete or overwrite-then-delete an
      # audit object or version — the audit trail is immutable for its retention
      # window. This does NOT block lifecycle expiration (internal S3 action) and
      # does NOT block the log services' PutObject (a create, not a delete).
      #
      # NOTE: PutBucketVersioning is deliberately NOT denied here. Denying it to
      # Principal "*" also denies the CI/terraform role (an explicit resource-
      # policy deny beats the identity-based allow), which self-locks the module
      # out of managing versioning at apply time. Versioning suspension is instead
      # gated by the IAM boundary (only the CI role holds s3:PutBucketVersioning).
      {
        Sid       = "DenyAuditObjectDeletion"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
        ]
        Resource = [
          aws_s3_bucket.audit_logs.arn,
          "${aws_s3_bucket.audit_logs.arn}/*"
        ]
      },
      {
        Sid    = "AllowALBAccessLogs"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.audit_logs.arn}/alb-logs/*"
      },
      {
        Sid    = "AllowALBLogDelivery"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.audit_logs.arn}/alb-logs/*"
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
        Resource = aws_s3_bucket.audit_logs.arn
      },
      {
        Sid    = "AllowS3AccessLogging"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.audit_logs.arn}/s3-access-logs/*"
        Condition = {
          ArnLike = {
            # The uploads bucket, the evidence bucket (#484), and the SES
            # inbound-mail bucket (#528) send their S3 server access logs here —
            # access to evidence/mail is itself audit-immutable.
            "aws:SourceArn" = [
              "arn:aws:s3:::${local.name_prefix}-uploads",
              "arn:aws:s3:::${local.name_prefix}-security-artifacts",
              "arn:aws:s3:::${local.name_prefix}-ses-inbound",
            ]
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
        Resource = aws_s3_bucket.audit_logs.arn
      },
      {
        Sid    = "AllowCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.audit_logs.arn}/cloudtrail/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
    ]
  })
}
