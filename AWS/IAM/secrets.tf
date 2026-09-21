# =============================================================================
# Break-Glass role — MFA-gated assume access to the admin secret
#
# Centralized here per the IAM-locality rule (#238). The admin secret resource
# stays in modules/secrets/. Policy references it via var.admin_secret_arn,
# which is already wired into iam from the secrets module.
# =============================================================================

resource "aws_iam_role" "break_glass" {
  count = var.break_glass_principal_arn != "" ? 1 : 0
  name  = "${local.name_prefix}-break-glass"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.break_glass_principal_arn }
      Action    = "sts:AssumeRole"
      Condition = {
        Bool = { "aws:MultiFactorAuthPresent" = "true" }
      }
    }]
  })

  tags = {
    Name = "${local.name_prefix}-break-glass"
  }
}

data "aws_iam_policy_document" "break_glass" {
  count = var.break_glass_principal_arn != "" ? 1 : 0

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.admin_secret_arn]
  }
}

resource "aws_iam_role_policy" "break_glass" {
  count  = var.break_glass_principal_arn != "" ? 1 : 0
  name   = "${local.name_prefix}-break-glass-access"
  role   = aws_iam_role.break_glass[0].id
  policy = data.aws_iam_policy_document.break_glass[0].json
}
