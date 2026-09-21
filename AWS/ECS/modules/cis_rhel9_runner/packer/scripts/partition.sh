#!/bin/bash
# cis-rhel9 golden AMI — LVM partition layout (#368 Phase 1b).
# Carves the extra EBS data volume (/dev/sdb or its NVMe alias) into LVM
# /var, /var/tmp, /home with CIS mount options. /var is migrated live (rsync)
# then remounted on reboot (packer reboots after this script). /var/log and
# /var/log/audit are intentionally NOT separate partitions — logs ship off-box
# (CloudWatch). Run as root.
set -euxo pipefail

# The RHEL-9 base AMI is minimal: install LVM + rsync + xfs tooling first.
dnf install -y lvm2 rsync xfsprogs

VAR_VOL_GB="${VAR_VOL_GB:-20}"
DEV=/dev/nvme1n1
[[ -b "$DEV" ]] || DEV=/dev/sdb
[[ -b "$DEV" ]] || { echo "ERROR: data volume not found (tried /dev/nvme1n1, /dev/sdb)" >&2; exit 1; }

# Sizing: ~60% /var, ~15% /var/tmp, remainder /home.
VAR_GB=$(( VAR_VOL_GB * 60 / 100 ))
VARTMP_GB=$(( VAR_VOL_GB * 15 / 100 ))

pvcreate -y "$DEV"
vgcreate vg_data "$DEV"
lvcreate -y -n lv_var    -L "${VAR_GB}G"    vg_data
lvcreate -y -n lv_vartmp -L "${VARTMP_GB}G" vg_data
lvcreate -y -n lv_home   -l 100%FREE        vg_data
for lv in lv_var lv_vartmp lv_home; do mkfs.xfs -f "/dev/vg_data/$lv"; done

# Migrate EACH mount point's existing content onto its LV before fstab points
# there — otherwise the empty LV shadows the originals on reboot. Critically,
# /home holds ec2-user/.ssh/authorized_keys (packer's temp key): skipping it
# wipes SSH access after the reboot. rsync exit 24 (files vanished mid-copy on
# live dirs) is benign for a fresh build box; anything else is fatal.
migrate() {
  local lv="$1" src="$2"
  mkdir -p /mnt/mig
  mount "/dev/vg_data/$lv" /mnt/mig
  rsync -aXS "$src/" /mnt/mig/ || { rc=$?; [[ "$rc" = "24" ]] || exit "$rc"; }
  umount /mnt/mig
}
migrate lv_var    /var
migrate lv_home   /home
migrate lv_vartmp /var/tmp

# fstab with CIS mount options (noexec on /var/tmp; /var keeps exec — RPM scriptlets).
cat >> /etc/fstab <<'FSTAB'
/dev/vg_data/lv_var     /var      xfs  defaults,nodev,nosuid         0 0
/dev/vg_data/lv_vartmp  /var/tmp  xfs  defaults,nodev,nosuid,noexec  0 0
/dev/vg_data/lv_home    /home     xfs  defaults,nodev,nosuid         0 0
FSTAB

# No /.autorelabel: rsync -X already copied security.selinux xattrs onto the LVs,
# so contexts are preserved. Avoid autorelabel's full-FS relabel + second reboot,
# which would desync packer's single post-reboot reconnect.
echo "partition.sh done: /var=${VAR_GB}G /var/tmp=${VARTMP_GB}G /home=remainder on $DEV"
