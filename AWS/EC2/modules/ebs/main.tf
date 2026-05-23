locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Encrypted EBS Volume
# ---------------------------------------------------------------------------

resource "aws_ebs_volume" "data" {
  availability_zone = var.availability_zone
  size              = var.volume_size
  type              = var.volume_type
  encrypted         = true
  kms_key_id        = var.kms_key_arn

  tags = {
    Name       = "${local.name_prefix}-data"
    MountPath  = var.mount_path
    DeviceName = var.device_name
  }
}

# ---------------------------------------------------------------------------
# Volume Attachment
# ---------------------------------------------------------------------------

resource "aws_volume_attachment" "data" {
  device_name = var.device_name
  volume_id   = aws_ebs_volume.data.id
  instance_id = var.instance_id
}
