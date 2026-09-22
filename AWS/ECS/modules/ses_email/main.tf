# =============================================================================
# ses_email — Amazon SES email handling for example.com (#528)
#
# Phase 1 (this file): domain identity + Easy DKIM + custom MAIL FROM, and all
# the Route53 records SES needs (verification TXT, DKIM CNAMEs, receiving MX,
# apex SPF, MAIL-FROM MX/SPF, DMARC). Phases 2-3 (inbound S3 bucket, receipt
# rule, forwarder Lambda, send-as SMTP) build on this once the domain verifies.
#
# Native AWS only (SES + Route53 here; S3 + Lambda in later phases). Route53 is
# the sole DNS authority — all records land in the existing example.com
# hosted zone (looked up, not managed here). IAM for later phases lives in
# modules/iam per the #238 locality rule.
# =============================================================================

# ---------------------------------------------------------------------------
# Domain identity + verification
# ---------------------------------------------------------------------------

resource "aws_ses_domain_identity" "domain" {
  domain = var.domain_name
}

resource "aws_route53_record" "verification" {
  zone_id = var.hosted_zone_id
  name    = "_amazonses.${var.domain_name}"
  type    = "TXT"
  ttl     = var.record_ttl
  records = [aws_ses_domain_identity.domain.verification_token]
}

resource "aws_ses_domain_identity_verification" "domain" {
  domain     = aws_ses_domain_identity.domain.id
  depends_on = [aws_route53_record.verification]
}

# ---------------------------------------------------------------------------
# Easy DKIM (3 CNAME tokens)
# ---------------------------------------------------------------------------

resource "aws_ses_domain_dkim" "domain" {
  domain = aws_ses_domain_identity.domain.domain
}

resource "aws_route53_record" "dkim" {
  count   = 3
  zone_id = var.hosted_zone_id
  name    = "${aws_ses_domain_dkim.domain.dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = var.record_ttl
  records = ["${aws_ses_domain_dkim.domain.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

# ---------------------------------------------------------------------------
# Custom MAIL FROM (bounce/complaint alignment for deliverability)
# ---------------------------------------------------------------------------

resource "aws_ses_domain_mail_from" "domain" {
  domain           = aws_ses_domain_identity.domain.domain
  mail_from_domain = "${var.mail_from_subdomain}.${var.domain_name}"
}

resource "aws_route53_record" "mail_from_mx" {
  zone_id = var.hosted_zone_id
  name    = aws_ses_domain_mail_from.domain.mail_from_domain
  type    = "MX"
  ttl     = var.record_ttl
  records = ["10 feedback-smtp.${var.aws_region}.amazonses.com"]
}

resource "aws_route53_record" "mail_from_spf" {
  zone_id = var.hosted_zone_id
  name    = aws_ses_domain_mail_from.domain.mail_from_domain
  type    = "TXT"
  ttl     = var.record_ttl
  records = ["v=spf1 include:amazonses.com -all"]
}

# ---------------------------------------------------------------------------
# Receiving MX (apex) + apex SPF + DMARC
# ---------------------------------------------------------------------------

# Inbound mail for the apex is delivered to the SES inbound endpoint. SES inbound
# is region-scoped (us-east-1 supported); the receipt rule set that acts on it is
# added in Phase 2.
resource "aws_route53_record" "inbound_mx" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "MX"
  ttl     = var.record_ttl
  records = ["10 inbound-smtp.${var.aws_region}.amazonaws.com"]
}

resource "aws_route53_record" "spf" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = var.record_ttl
  records = ["v=spf1 include:amazonses.com -all"]
}

resource "aws_route53_record" "dmarc" {
  zone_id = var.hosted_zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = var.record_ttl
  # Start in monitor mode (p=none) for a new domain — tighten to quarantine/reject
  # after DKIM/SPF alignment is confirmed via the aggregate (rua) reports.
  records = ["v=DMARC1; p=${var.dmarc_policy}; rua=mailto:${var.dmarc_rua}; fo=1"]
}

# ===========================================================================
# Phase 2 (#528) — inbound S3 store + receipt rule
#
# The receipt rule is added to the EXISTING active INBOUND_MAIL rule set
# (WorkMail's, serving .info/.awsapps.com) — recipients don't overlap. We do
# NOT create/activate a new rule set (that would deactivate INBOUND_MAIL).
# ===========================================================================

data "aws_iam_policy_document" "inbound_bucket" {
  count = var.enable_inbound ? 1 : 0

  # SES writes received mail here. Scoped to this account's SES.
  statement {
    sid       = "AllowSESPut"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.inbound_bucket_name}/*"]
    principals {
      type        = "Service"
      identifiers = ["ses.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }
  }

  # Deny any request that isn't over TLS (defense-in-depth; SES writes over TLS).
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.inbound_bucket_name}",
      "arn:aws:s3:::${var.inbound_bucket_name}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# NOTE for reviewers/SonarQube (S6258 server-access-logging, S6249 HTTPS-only):
# both controls ARE enforced, but the AWS provider v5 removed the inline
# `logging`/`policy` arguments on aws_s3_bucket, so they live in dedicated
# resources below and SonarQube's per-resource hotspot cannot associate them:
#   - server access logging -> aws_s3_bucket_logging.inbound (WORM audit bucket)
#   - HTTPS-only            -> aws_s3_bucket_policy.inbound / DenyInsecureTransport
# Disposition these two hotspots as "Safe" in the SonarQube review UI.
resource "aws_s3_bucket" "inbound" {
  count  = var.enable_inbound ? 1 : 0
  bucket = var.inbound_bucket_name
  tags   = { Name = var.inbound_bucket_name, Purpose = "ses-inbound-mail" }
}

resource "aws_s3_bucket_public_access_block" "inbound" {
  count                   = var.enable_inbound ? 1 : 0
  bucket                  = aws_s3_bucket.inbound[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "inbound" {
  count  = var.enable_inbound ? 1 : 0
  bucket = aws_s3_bucket.inbound[0].id
  rule {
    # SSE-S3 (AES256): SES-inbound compatible without granting SES a CMK; the
    # raw mail is transient (lifecycle-expired) and read only by the forwarder.
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "inbound" {
  count  = var.enable_inbound ? 1 : 0
  bucket = aws_s3_bucket.inbound[0].id
  rule {
    id     = "expire-forwarded-mail"
    status = "Enabled"
    filter {}
    expiration { days = var.inbound_retention_days }
  }
}

resource "aws_s3_bucket_policy" "inbound" {
  count  = var.enable_inbound ? 1 : 0
  bucket = aws_s3_bucket.inbound[0].id
  policy = data.aws_iam_policy_document.inbound_bucket[0].json
}

resource "aws_ses_receipt_rule" "forward" {
  count         = var.enable_inbound ? 1 : 0
  name          = "risk-sentinel-org-forward"
  rule_set_name = var.receipt_rule_set_name
  recipients    = var.recipients
  enabled       = true
  scan_enabled  = true

  # Store the raw message, then invoke the forwarder Lambda.
  s3_action {
    position          = 1
    bucket_name       = var.inbound_bucket_name
    object_key_prefix = var.inbound_prefix
  }
  lambda_action {
    position        = 2
    function_arn    = var.forwarder_lambda_arn
    invocation_type = "Event"
  }

  depends_on = [aws_s3_bucket_policy.inbound]
}

resource "aws_s3_bucket_versioning" "inbound" {
  count  = var.enable_inbound ? 1 : 0
  bucket = aws_s3_bucket.inbound[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 server access logs → the WORM audit bucket (same sink as uploads/evidence,
# #484). The audit bucket's AllowS3AccessLogging statement authorizes delivery
# for this bucket's ARN; disabling logging on the inbound bucket itself is not
# an option here (it is not its own log target).
resource "aws_s3_bucket_logging" "inbound" {
  count         = var.enable_inbound ? 1 : 0
  bucket        = aws_s3_bucket.inbound[0].id
  target_bucket = var.log_bucket_name
  target_prefix = "s3-access-logs/"
}

# ===========================================================================
# Phase 3 (#528) — destination verification (sandbox send-as)
#
# SES is in the sandbox, so it can only send to verified addresses. Verifying
# the forward destinations lets the forwarder deliver without requesting
# production access. Each triggers a one-time confirmation email to click.
# ===========================================================================

resource "aws_ses_email_identity" "destinations" {
  for_each = var.enable_inbound ? toset(var.destinations) : toset([])
  email    = each.value
}
