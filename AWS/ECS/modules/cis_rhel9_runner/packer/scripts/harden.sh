#!/bin/bash
# cis-rhel9 golden AMI — ansible-lockdown/RHEL9-CIS Level 1 (#368 Phase 1b).
# Runs the role locally on the build box. Partitions are already handled
# (partition.sh); /tmp + /dev/shm are handled at runtime in user_data (PR1);
# /var/log* + audit retention ship off-box (CloudWatch), so those sections are
# disabled here. Run as root.
set -euxo pipefail

ANSIBLE_REF="${ANSIBLE_REF:-1.3.0}"

# python3-jmespath: ansible's json_query filter (used by the role's SUID audit) needs it.
dnf install -y ansible-core git rsync python3-jmespath
ansible-galaxy collection install ansible.posix community.general ansible.utils

git clone --depth 1 --branch "$ANSIBLE_REF" \
  https://github.com/ansible-lockdown/RHEL9-CIS.git /opt/RHEL9-CIS

# ansible-lockdown's anti-lockout preflights assert both the login user AND root
# have a password set before it hardens auth. This box is SSM-only (no password
# login), so set throwaway random passwords to satisfy the asserts without
# affecting access (SSM/sudo are unchanged).
echo "ec2-user:$(openssl rand -base64 24)" | chpasswd
echo "root:$(openssl rand -base64 24)" | chpasswd

cat > /opt/cis-playbook.yml <<'PB'
- hosts: localhost
  connection: local
  become: true
  vars:
    rhel9cis_level_1: true
    rhel9cis_level_2: false
    # Partitions handled by partition.sh; /tmp + /dev/shm in user_data (PR1).
    rhel9cis_rule_1_1_2_1: false   # /tmp (tmpfs in user_data)
    rhel9cis_rule_1_1_2_2: false   # /dev/shm (user_data)
    rhel9cis_rule_1_1_2_6: false   # /var/log separate partition (off-box CloudWatch)
    rhel9cis_rule_1_1_2_7: false   # /var/log/audit separate partition (off-box)
    rhel9cis_rule_1_4_1: false     # bootloader password (no Nitro console)
    rhel9cis_config_aide: true
  roles:
    - /opt/RHEL9-CIS
PB

ansible-playbook /opt/cis-playbook.yml
echo "harden.sh done: ansible-lockdown RHEL9-CIS @ ${ANSIBLE_REF}"
