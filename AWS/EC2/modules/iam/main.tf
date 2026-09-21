locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# EC2 Instance Role (assume role for EC2 service)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${local.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${local.name_prefix}-ec2-role"
  }
}

# ---------------------------------------------------------------------------
# Instance Profile
# ---------------------------------------------------------------------------

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-instance-profile"
  role = aws_iam_role.ec2.name

  tags = {
    Name = "${local.name_prefix}-ec2-instance-profile"
  }
}

# ---------------------------------------------------------------------------
# Managed Policy — SSM (Session Manager, no SSH needed)
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ---------------------------------------------------------------------------
# Managed Policy — CloudWatch Agent
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ---------------------------------------------------------------------------
# Inline Policy — Secrets Manager access
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "secrets_access" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      var.db_secret_arn,
      var.app_secret_arn,
    ]
  }
}

resource "aws_iam_role_policy" "secrets" {
  name   = "${local.name_prefix}-secrets-access"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.secrets_access.json
}

# ---------------------------------------------------------------------------
# Inline Policy — S3 access for ActiveStorage uploads
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "s3_access" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      var.s3_bucket_arn,
      "${var.s3_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "s3" {
  name   = "${local.name_prefix}-s3-access"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.s3_access.json
}
