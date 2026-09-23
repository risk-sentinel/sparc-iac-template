# =============================================================================
# SES SMTP send-as user (#528 Phase 3)
#
# SES SMTP requires long-lived IAM-user credentials (there is no OIDC/role path
# for SMTP). The v4-derived SMTP password is surfaced (sensitive) for one-time
# mail-client configuration (iCloud / ATT). Scope: ses:SendRawEmail only.
# =============================================================================

resource "aws_iam_user" "ses_smtp" {
  count = var.enable_ses_smtp ? 1 : 0
  name  = "${local.name_prefix}-ses-smtp"
  tags  = { Name = "${local.name_prefix}-ses-smtp" }
}

resource "aws_iam_access_key" "ses_smtp" {
  count = var.enable_ses_smtp ? 1 : 0
  user  = aws_iam_user.ses_smtp[0].name
}

data "aws_iam_policy_document" "ses_smtp" {
  count = var.enable_ses_smtp ? 1 : 0
  statement {
    sid       = "SESSendAs"
    actions   = ["ses:SendRawEmail"]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "ses_smtp" {
  count  = var.enable_ses_smtp ? 1 : 0
  name   = "ses-smtp-send"
  user   = aws_iam_user.ses_smtp[0].name
  policy = data.aws_iam_policy_document.ses_smtp[0].json
}
