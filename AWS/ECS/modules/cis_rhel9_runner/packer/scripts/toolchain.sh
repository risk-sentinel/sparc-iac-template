#!/bin/bash
# cis-rhel9 golden AMI — scan toolchain (#374). Baked at BUILD time so the runner
# boots scan-ready instead of installing everything in user_data each launch
# (kills the #351/#363/#365/#366 boot-time install fragility). Runs BEFORE
# harden.sh — must use passwordless sudo, which harden.sh's CIS 5.2.x sudo
# lockdown removes. Versions via env.
set -euxo pipefail

SAF_VERSION="${SAF_VERSION:-1.6.0}"
CINC_VERSION="${CINC_VERSION:-7.0.107}"
HDF_VERSION="${HDF_VERSION:-3.2.0}"
REGION="${REGION:-us-east-1}"

retry() { local n=0; until "$@"; do n=$((n+1)); [[ "$n" -ge 5 ]] && return 1; echo "retry $n: $*"; sleep $((n*10)); done; }

ARCH=$(uname -m)
CLI_ARCH=aarch64; ASSET_ARCH=arm64
[[ "$ARCH" = "x86_64" ]] && CLI_ARCH=x86_64 && ASSET_ARCH=amd64

# --- AWS CLI v2 (curl + python3 unzip; no 'unzip' pkg) ---
if ! command -v aws >/dev/null 2>&1; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$CLI_ARCH.zip" -o /tmp/awscliv2.zip
  python3 -c "import zipfile; zipfile.ZipFile('/tmp/awscliv2.zip').extractall('/tmp')"
  chmod -R +x /tmp/aws
  /tmp/aws/install
fi

# --- Build deps + Node 22 (module 'common' profile pulls node AND npm) ---
retry dnf install -y git tar gcc gcc-c++ make
dnf module reset -y nodejs || true
retry dnf module install -y nodejs:22/common

# --- MITRE toolchain: saf, hdf-converters, cinc-auditor, hdf CLI ---
retry npm install -g "@mitre/saf@${SAF_VERSION}"
retry npm install -g @mitre/hdf-converters
retry bash -c "curl -fsSL https://omnitruck.cinc.sh/install.sh | bash -s -- -P cinc-auditor -v ${CINC_VERSION}"
retry bash -c "curl -fsSL https://github.com/mitre/hdf-libs/releases/download/v${HDF_VERSION}/hdf_${HDF_VERSION}_linux_${ASSET_ARCH}.tar.gz -o /tmp/hdf.tgz"
tar xzf /tmp/hdf.tgz -C /tmp hdf && install -m 0755 /tmp/hdf /usr/bin/hdf
# saf installs under npm's /usr/local prefix (absent from login-shell PATH) — symlink so it resolves everywhere.
[[ -x /usr/local/bin/saf ]] && ln -sf /usr/local/bin/saf /usr/bin/saf

# --- CloudWatch agent (binary baked; the config stays in user_data, instance-id-specific) ---
retry rpm -Uvh --replacepkgs "https://amazoncloudwatch-agent-${REGION}.s3.${REGION}.amazonaws.com/redhat/${ASSET_ARCH}/latest/amazon-cloudwatch-agent.rpm"

# --- psql CLIENT only (DB/postgres profile scanning); NOT postgresql-server ---
retry dnf install -y postgresql

echo "toolchain.sh done: saf=$(saf --version 2>&1) cinc=$(cinc-auditor version 2>&1 | head -1) hdf=$(hdf version 2>&1 | head -1) node=$(node --version 2>&1) psql=$(psql --version 2>&1)"
