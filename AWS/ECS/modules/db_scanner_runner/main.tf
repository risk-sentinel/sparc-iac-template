# =============================================================================
# sparc-validate DB Scanner — Ephemeral VPC Runner (#188)
#
# Zero-idle-cost self-hosted GitHub Actions runner. sparc-validate's workflow
# scales the ASG to 1 before a DB compliance scan, the instance registers as
# an ephemeral runner, runs one scan job, then self-terminates. The workflow's
# cleanup step scales the ASG back to 0.
#
# Idle cost: $0. Per-scan cost: ~$0.01 at one daily scan.
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  asg_name    = "${local.name_prefix}-db-scanner-runner"

  # Pin precedence (#245): an operator-set var.runner_ami_id wins; otherwise
  # fall back to the most_recent Canonical lookup below. Prod sets the pin in
  # root main.tf so applies are drift-free against AMI publishes; the
  # fallback path is for first-bring-up / non-prod stacks where chasing the
  # latest image is desirable.
  runner_ami_id = var.runner_ami_id != "" ? var.runner_ami_id : data.aws_ami.runner[0].id
}

# -----------------------------------------------------------------------------
# AMI — Ubuntu 24.04 LTS ARM64 (Canonical)
#
# AL2023 was the obvious default but was rejected per #188 design review
# (EOL June 2026 per project policy). Ubuntu 24.04 "noble" has Canonical
# standard support through April 2029 and ESM through 2036.
#
# Data source is gated: when var.runner_ami_id is set the count is 0 so the
# lookup is skipped entirely (#245).
# -----------------------------------------------------------------------------

data "aws_ami" "runner" {
  count       = var.runner_ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# -----------------------------------------------------------------------------
# Security groups
# -----------------------------------------------------------------------------

resource "aws_security_group" "runner" {
  name_prefix = "${local.asg_name}-"
  description = "sparc-validate DB scanner ephemeral runner - egress to Aurora and GitHub only; no ingress."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.asg_name}-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "runner_egress_aurora" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = var.aurora_sg_id
  security_group_id        = aws_security_group.runner.id
  description              = "Aurora PostgreSQL for IAM DB auth (#184 dbuser)"
}

resource "aws_security_group_rule" "runner_egress_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.runner.id
  description       = "GitHub API + Actions control-plane + SSM endpoints"
}

resource "aws_security_group_rule" "runner_egress_http" {
  # Needed for apt package fetch during user-data if the AMI doesn't have
  # everything pre-baked. Scoped to port 80 only, egress only.
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.runner.id
  description       = "Ubuntu package repos (apt) during bootstrap"
}

resource "aws_security_group_rule" "aurora_ingress_from_runner" {
  # Attach to the Aurora SG so the runner can actually reach the cluster.
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.runner.id
  security_group_id        = var.aurora_sg_id
  description              = "sparc-validate db-scanner runner - IAM DB auth (#188)"
}

# -----------------------------------------------------------------------------
# Launch template
# -----------------------------------------------------------------------------

resource "aws_launch_template" "runner" {
  name_prefix            = "${local.asg_name}-"
  image_id               = local.runner_ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.runner.id]
  update_default_version = true

  iam_instance_profile {
    arn = var.instance_profile_arn
  }

  # IMDSv2 only (CKV_AWS_79 + CKV_AWS_341 hop limit)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Encrypted root volume
  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    github_org                 = var.github_org
    github_repo                = var.github_repo
    runner_version             = var.runner_version
    runner_labels              = join(",", var.runner_labels)
    cinc_auditor_version       = var.cinc_auditor_version
    app_key_secret_name        = aws_secretsmanager_secret.runner_app_key.name
    aws_region                 = data.aws_region.current.name
    db_credentials_secret_name = var.db_credentials_secret_name
    # base64gzip sidesteps Terraform interpolation parsing of the bash $${...}
    # patterns in these scripts AND compresses to fit under EC2's 16 KiB
    # user_data limit (#245 apply caught the overflow at 18 KiB raw). The
    # runner decodes via `base64 -d | gunzip` — both binaries are in the
    # Ubuntu 24.04 base image. Source of truth: AWS/ECS/scripts/.
    bootstrap_script_b64gz = base64gzip(file("${path.root}/scripts/bootstrap-inspec-scanner-runner.sh"))
    bootstrap_sql_b64gz    = base64gzip(file("${path.root}/scripts/inspec_scanner.sql"))
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = local.asg_name
      Purpose = "db-compliance-scanner-runner"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling Group — desired=0 at rest, scaled to 1 by sparc-validate orchestration
# -----------------------------------------------------------------------------

resource "aws_autoscaling_group" "runner" {
  name                = local.asg_name
  min_size            = 0
  max_size            = 1
  desired_capacity    = 0
  vpc_zone_identifier = var.private_subnet_ids

  health_check_type         = "EC2"
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.runner.id
    version = "$Latest"
  }

  # Instance self-shutdown on scan completion drains the ASG — desired stays
  # at whatever sparc-validate's orchestration set it to. The orchestration's
  # cleanup job explicitly scales back to 0 as part of always() cleanup.
  instance_maintenance_policy {
    min_healthy_percentage = 0
    max_healthy_percentage = 100
  }

  tag {
    key                 = "Name"
    value               = local.asg_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Purpose"
    value               = "db-compliance-scanner-runner"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    # sparc-validate orchestration owns desired_capacity at runtime —
    # scales to 1 via autoscaling:SetDesiredCapacity at scan start, back
    # to 0 at scan completion via always() cleanup. Terraform must stop
    # reconciling this attribute or deploy-on-merge will terminate
    # runners mid-scan (witnessed PR #305 cascade 2026-05-25 — sparc-iac#307).
    # See instance_maintenance_policy comment above for the orchestration
    # contract.
    ignore_changes = [desired_capacity]
  }
}

# -----------------------------------------------------------------------------
# CloudWatch alarm — "instance running > N minutes" proxy for stuck runners
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "stuck_runner" {
  alarm_name          = "${local.asg_name}-stuck"
  alarm_description   = "sparc-validate DB scanner runner has been running longer than ${var.stuck_runner_alarm_minutes} minutes - likely failed to register, stuck mid-scan, or orchestration cleanup failed."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = var.stuck_runner_alarm_minutes * 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.runner.name
  }

  alarm_actions = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  ok_actions    = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
