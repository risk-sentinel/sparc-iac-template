# =============================================================================
# cis-rhel-9 exec-validation test instance (#351)
#
# A RHEL-9, SSM-only EC2 target to exec-validate the cis-rhel-9 cinc profile
# against a real RHEL-9 host. Mirrors the db_scanner_runner pattern: private
# subnet, NAT egress, SSM-managed, scale-to-0 ASG (idle cost $0).
#
# - On-demand: scale desired 0<->1 (see .github/workflows/cis-rhel9-runner.yml).
# - Auto-off: an on-instance systemd timer scales its own ASG to 0 at 21:00
#   America/Chicago (catches a left-up box). No aws_autoscaling_schedule, so no
#   bootstrap/oidc grant needed — the SetDesiredCapacity permission rides on the
#   instance role (modules/iam/cis_rhel9_runner.tf).
# - Test-only: not in the prod compliance-scan matrix.
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  asg_name    = "${local.name_prefix}-cis-rhel9-runner"

  # Off-box logging (#368): auditd + system logs ship here via the CloudWatch
  # agent. The IAM grant in modules/iam/cis_rhel9_runner.tf scopes to this same
  # constructed name (#238 IAM-locality).
  log_group_name = "/cis-rhel9/${local.asg_name}"

  # AMI precedence (#368): newest self-built GOLDEN AMI (packer, Phase 1b) wins so
  # the honeypot auto-adopts each new hardened image; else the operator pin
  # (var.ami_id, the RHEL-9.6 determinism pin); else the most_recent RHEL-9 base.
  # The golden lookup is existence-guarded, so before the first build the honeypot
  # falls back to the pin/base and still launches.
  golden_ami_id = length(data.aws_ami.golden) > 0 ? data.aws_ami.golden[0].id : ""
  ami_id        = local.golden_ami_id != "" ? local.golden_ami_id : (var.ami_id != "" ? var.ami_id : data.aws_ami.rhel9[0].id)
}

# -----------------------------------------------------------------------------
# AMI — RHEL 9 arm64 (Red Hat official, owner 309956199498).
# arm64/t4g matches the Graviton fleet; cinc checks are arch-agnostic (#351).
# Gated: skipped entirely when var.ami_id is pinned.
# -----------------------------------------------------------------------------

data "aws_ami" "rhel9" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["309956199498"] # Red Hat

  filter {
    name   = "name"
    values = ["RHEL-9*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# Off-box logging (#368) — CloudWatch log group for auditd + system logs.
# CloudWatch is the compensating control for on-box audit retention; off-box
# shipping is tamper-resistant from the host. KMS via logs_key_arn when CMK is on.
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "rhel9" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = {
    Name    = "${local.asg_name}-logs"
    Purpose = "cis-rhel9-exec-validation"
  }
}

# -----------------------------------------------------------------------------
# Security group — egress only, no ingress (SSM is outbound-initiated).
# -----------------------------------------------------------------------------

resource "aws_security_group" "rhel9" {
  name_prefix = "${local.asg_name}-"
  description = "cis-rhel-9 exec-validation test instance - egress only (SSM/GitHub/omnitruck/npm/S3); no ingress."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.asg_name}-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "rhel9_egress_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rhel9.id
  description       = "SSM endpoints, GitHub profile, cinc omnitruck, npm registry, S3 (via NAT), autoscaling API"
}

resource "aws_security_group_rule" "rhel9_egress_http" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rhel9.id
  description       = "RHEL/dnf package repos during bootstrap"
}

# -----------------------------------------------------------------------------
# Launch template — hardening mirrors db_scanner_runner (IMDSv2, encrypted gp3,
# detailed monitoring) so checkov stays clean.
# -----------------------------------------------------------------------------

resource "aws_launch_template" "rhel9" {
  name_prefix            = "${local.asg_name}-"
  image_id               = local.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.rhel9.id]
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

  # Encrypted root volume (CKV_AWS_8) — 30 GiB headroom for cinc/node/saf.
  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Data volume (#368) carrying the golden AMI's LVM /var //var/tmp //home.
  # Declared explicitly so size/encryption/delete-on-termination aren't implicit
  # from the resolved AMI's block-device mapping. On the pre-golden base AMI this
  # is an unused blank volume (the LVM lives only in the golden image).
  block_device_mappings {
    device_name = "/dev/sdb"

    ebs {
      volume_size           = var.data_volume_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region     = data.aws_region.current.name
    asg_name       = local.asg_name
    results_bucket = var.results_bucket_name
    results_prefix = var.results_prefix
    log_group_name = local.log_group_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = local.asg_name
      Purpose = "cis-rhel9-exec-validation"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling Group — desired=0 at rest; scaled to 1 on demand (workflow) and
# back to 0 by the on-instance 9pm self-off timer or the workflow.
# -----------------------------------------------------------------------------

resource "aws_autoscaling_group" "rhel9" {
  name                = local.asg_name
  min_size            = 0
  max_size            = 1
  desired_capacity    = 0
  vpc_zone_identifier = var.private_subnet_ids

  health_check_type         = "EC2"
  health_check_grace_period = 300 # cinc/node/saf install in user-data takes a few minutes

  launch_template {
    id      = aws_launch_template.rhel9.id
    version = "$Latest"
  }

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
    value               = "cis-rhel9-exec-validation"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    # desired_capacity is owned at runtime by the on-demand workflow and the
    # on-instance 9pm self-off timer (autoscaling:SetDesiredCapacity). Terraform
    # must not reconcile it or a deploy would tear down an in-use test box
    # (mirror db_scanner_runner #307).
    ignore_changes = [desired_capacity]
  }
}

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Golden AMI auto-resolution (#368 Phase 1b) — newest self-built golden image.
# Existence-guarded via aws_ami_ids so a fresh environment with no golden image
# yet falls back to the operator pin / RHEL-9 base (data.aws_ami.golden = []).
# Built by .github/workflows/cis-rhel9-golden-ami.yml (packer); named
# "<asg_name>-golden-<timestamp>".
# -----------------------------------------------------------------------------

data "aws_ami_ids" "golden_check" {
  owners = ["self"]
  filter {
    name   = "name"
    values = ["${local.asg_name}-golden-*"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ami" "golden" {
  count       = length(data.aws_ami_ids.golden_check.ids) > 0 ? 1 : 0
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "name"
    values = ["${local.asg_name}-golden-*"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}
