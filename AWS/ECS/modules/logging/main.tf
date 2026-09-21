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

# WORM (#336) — enable Object Lock IN-PLACE on the existing versioning-enabled
# bucket. Deliberately does NOT set object_lock_enabled on aws_s3_bucket (that
# flag is ForceNew → would replace the bucket); this resource's
# PutObjectLockConfiguration enables it without recreation. No `rule {}` = no
# bucket-wide default retention (ALB logs share this bucket); retention is
# applied per-object on the evidence prefixes at PUT time (sparc-validate#153).
#
# The CI role's s3:PutBucketObjectLockConfiguration grant (bootstrap/oidc/
# policy.tf, applied 2026-06-03) is the prerequisite — the first #336 attempt
# (PR #338) failed AccessDenied without it (hotfix #339), so this resource was
# held until the grant landed. See feedback_new_aws_action_needs_ci_grant.
resource "aws_s3_bucket_object_lock_configuration" "artifacts" {
  bucket              = aws_s3_bucket.artifacts.id
  object_lock_enabled = "Enabled"
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
# Bucket Policy — evidence bucket (CI-writable). The audit-immutable log
# writers (CloudTrail / Config / ALB / S3-access) moved to the dedicated
# `${name_prefix}-audit-logs` bucket in #484 (see audit_logs.tf); only the
# SSL-only guard and the evidence-encryption guard remain here.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
      # WORM (#336): evidence must land SSE-KMS-encrypted. Scoped to the
      # evidence prefixes only. The evidence writer (sparc-validate#153) must
      # send `s3:x-amz-server-side-encryption=aws:kms`.
      {
        Sid       = "DenyUnencryptedEvidencePuts"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        # #721 — re-extended to the canonical #537 layout after the #715/#719
        # revert, once every producer was measured to send the header.
        #
        # This condition reads the REQUEST header, not the resulting object.
        # Default bucket encryption does not populate it, so "objects are
        # encrypted" and "the deny is satisfied" are different statements —
        # assuming otherwise is what took estate-wide emission down in #719.
        #
        # Producers were cleared from CloudTrail S3 data events rather than from
        # run logs or reusable pin tables, because the trail records both halves
        # of the question per request:
        #
        #   requestParameters."x-amz-server-side-encryption"  present only if sent
        #   additionalEventData.SSEApplied                    SSE_KMS if requested,
        #                                                     Default_SSE_KMS if the
        #                                                     bucket default supplied it
        #
        # Over 2026-09-19..20, 4,837 successful writes split 3,742 SSE_KMS /
        # 1,095 Default_SSE_KMS with no cross terms, and the most recent write
        # from all 24 active producers carried the header. The 101 AccessDenied
        # events in that window all fall inside the #719 outage, none after.
        #
        # The remaining roles that can write here assume nothing today: four are
        # verified compliant or inert, five have no caller in any repository and
        # are removed under #735.
        Resource = concat(
          [
            "${aws_s3_bucket.artifacts.arn}/attestations/*",
            "${aws_s3_bucket.artifacts.arn}/leveraged-systems/*",
          ],
          [for b in var.evidence_boundaries : "${aws_s3_bucket.artifacts.arn}/${b}/*"]
        )
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# S3 Access Logging — server access logs land in the audit-immutable bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_logging" "uploads" {
  count  = var.enable_uploads_bucket_logging ? 1 : 0
  bucket = var.uploads_bucket_id

  # #484 — S3 server access logs are audit-immutable → dedicated audit bucket.
  target_bucket = aws_s3_bucket.audit_logs.id
  target_prefix = "s3-access-logs/"
}

# #484 — log read/write access to the evidence bucket itself into the WORM
# audit bucket (AU-9). Previously the evidence bucket was implicitly exempt
# from access-logging because it WAS the access-log target; now that the sinks
# moved, log it explicitly. Delivery is authorized by the AllowS3AccessLogging
# statement in audit_logs.tf (SourceArn includes the evidence bucket).
resource "aws_s3_bucket_logging" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  target_bucket = aws_s3_bucket.audit_logs.id
  target_prefix = "s3-access-logs/"
}
