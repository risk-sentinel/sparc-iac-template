# =============================================================================
# cis-rhel9 golden AMI — packer (#368 Phase 1b / PR3, NO BOOTSTRAP)
#
# Builds the persistent-posture hardened AMI out-of-band: a throwaway RHEL-9
# arm64 box (private subnet, connected over SSM — no SSH ingress), with
#   1. LVM /var, /var/tmp, /home (CIS mount options)   — scripts/partition.sh
#   2. ansible-lockdown/RHEL9-CIS Level 1               — scripts/harden.sh
# Run by .github/workflows/cis-rhel9-golden-ami.yml under the self-service
# build role (modules/iam/cis_rhel9_runner.tf). Pin the output AMI via
# cis_rhel9_runner_ami_id. /var/log + /var/log/audit ship off-box (CloudWatch,
# PR1), so they are NOT separate partitions here.
# =============================================================================

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.0"
    }
  }
}

variable "region" { type = string }
variable "subnet_id" { type = string }
variable "security_group_id" { type = string }
variable "build_instance_profile" { type = string }
variable "instance_type" {
  type    = string
  default = "t4g.medium"
}
variable "var_volume_gb" {
  type    = number
  default = 20
}
variable "ansible_ref" {
  type    = string
  default = "1.3.0"
}
variable "saf_version" {
  type    = string
  default = "1.6.0"
}
variable "cinc_version" {
  type    = string
  default = "7.0.107"
}
variable "hdf_version" {
  type    = string
  default = "3.2.0"
}
variable "kms_key_id" {
  type    = string
  default = ""
}
variable "ami_name_prefix" {
  type    = string
  default = "example-cis-rhel9-runner-golden"
}

source "amazon-ebs" "golden" {
  region        = var.region
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  # Private subnet, no public IP; connect over SSM (no SSH ingress).
  associate_public_ip_address = false
  iam_instance_profile        = var.build_instance_profile
  security_group_id           = var.security_group_id
  communicator                = "ssh"
  ssh_username                = "ec2-user"
  ssh_interface               = "session_manager"

  # The Red Hat RHEL-9 base has no SSM agent; install it at boot (cloud-init,
  # before packer connects) so the session_manager interface works. arm64 rpm
  # from the regional amazon-ssm bucket (same source as the runner user_data).
  user_data = <<-EOT
    #!/bin/bash
    rpm -Uvh --replacepkgs "https://amazon-ssm-${var.region}.s3.${var.region}.amazonaws.com/latest/linux_arm64/amazon-ssm-agent.rpm"
    systemctl enable --now amazon-ssm-agent
  EOT

  # Latest Red Hat RHEL-9 arm64 as the base.
  source_ami_filter {
    filters = {
      name                = "RHEL-9*"
      architecture        = "arm64"
      virtualization-type = "hvm"
    }
    owners      = ["309956199498"]
    most_recent = true
  }

  # Root volume + an extra data volume for the LVM partitions. Encrypted (CMK
  # when kms_key_id is provided, AWS-managed otherwise).
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    kms_key_id            = var.kms_key_id != "" ? var.kms_key_id : null
    delete_on_termination = true
  }
  launch_block_device_mappings {
    device_name           = "/dev/sdb"
    volume_size           = var.var_volume_gb
    volume_type           = "gp3"
    encrypted             = true
    kms_key_id            = var.kms_key_id != "" ? var.kms_key_id : null
    delete_on_termination = true
  }

  encrypt_boot = true
  kms_key_id   = var.kms_key_id != "" ? var.kms_key_id : null

  ami_name        = "${var.ami_name_prefix}-{{timestamp}}"
  ami_description = "cis-rhel9 persistent-posture golden AMI (LVM partitions + ansible-lockdown RHEL9-CIS L1) (#368)"

  tags = {
    Name    = var.ami_name_prefix
    Purpose = "cis-rhel9-exec-validation"
    Posture = "persistent-cis-l1"
  }
}

build {
  sources = ["source.amazon-ebs.golden"]

  # 1. LVM partitions (/var, /var/tmp, /home) — runs as root, env-driven.
  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    environment_vars = ["VAR_VOL_GB=${var.var_volume_gb}"]
    script          = "${path.root}/scripts/partition.sh"
  }

  # 2. Reboot so the new fstab mounts (/var on its LV) take effect cleanly.
  provisioner "shell" {
    execute_command   = "sudo -E bash '{{ .Path }}'"
    expect_disconnect = true
    inline            = ["echo rebooting for partition mounts; sleep 2; reboot"]
  }

  # 3. Bake the scan toolchain (#374) — BEFORE harden.sh. Must run while ec2-user
  # still has passwordless sudo: harden.sh's CIS sudo lockdown (5.2.x require-
  # password + use_pty) removes it, which would break packer's `sudo -E bash` for
  # any later provisioner. Running hardening LAST also lets it have the final say
  # over anything the toolchain introduced (perms/audit).
  provisioner "shell" {
    execute_command     = "sudo -E bash '{{ .Path }}'"
    pause_before        = "45s"
    start_retry_timeout = "10m"
    environment_vars = [
      "SAF_VERSION=${var.saf_version}",
      "CINC_VERSION=${var.cinc_version}",
      "HDF_VERSION=${var.hdf_version}",
      "REGION=${var.region}",
    ]
    script = "${path.root}/scripts/toolchain.sh"
  }

  # 4. ansible-lockdown RHEL9-CIS Level 1 — LAST (its sudo hardening must not
  # precede any sudo-dependent provisioner).
  provisioner "shell" {
    execute_command  = "sudo -E bash '{{ .Path }}'"
    environment_vars = ["ANSIBLE_REF=${var.ansible_ref}"]
    script           = "${path.root}/scripts/harden.sh"
  }

  post-processor "manifest" {
    output     = "golden-ami-manifest.json"
    strip_path = true
  }
}
