#!/bin/bash
set -euo pipefail

# ===========================================================================
# SPARC Azure VM Bootstrap — User Data Script
# ===========================================================================
# Runs on first boot to install Docker, mount data disk, retrieve secrets
# from Key Vault, and start SPARC via docker-compose.
# Variables are injected by Terraform via templatefile().
# ===========================================================================

exec > >(tee /var/log/sparc-bootstrap.log) 2>&1
echo "=== SPARC bootstrap started at $(date) ==="

# ── Install Docker ──────────────────────────────────────────────────────────
apt-get update -y
apt-get install -y docker.io jq curl apt-transport-https
systemctl enable docker
systemctl start docker

# Install docker-compose plugin
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# ── Mount Data Disk ─────────────────────────────────────────────────────────
DISK_DEVICE="/dev/disk/azure/scsi1/lun${disk_lun}"
MOUNT_PATH="${disk_mount_path}"

# Wait for the disk to appear
while [ ! -e "$DISK_DEVICE" ]; do
  echo "Waiting for data disk at $DISK_DEVICE..."
  sleep 5
done

# Format if not already formatted
if ! blkid "$DISK_DEVICE"; then
  mkfs.xfs "$DISK_DEVICE"
fi

mkdir -p "$MOUNT_PATH"
mount "$DISK_DEVICE" "$MOUNT_PATH"
echo "$DISK_DEVICE $MOUNT_PATH xfs defaults,nofail 0 2" >> /etc/fstab

mkdir -p "$MOUNT_PATH"/{uploads,logs}
chown -R 1000:1000 "$MOUNT_PATH"

# ── Login with Managed Identity ─────────────────────────────────────────────
az login --identity --allow-no-subscriptions

# ── Retrieve secrets from Key Vault ─────────────────────────────────────────
KEY_VAULT="${key_vault_name}"

DB_SECRET=$(az keyvault secret show \
  --vault-name "$KEY_VAULT" \
  --name "${db_secret_name}" \
  --query value -o tsv)

APP_SECRET=$(az keyvault secret show \
  --vault-name "$KEY_VAULT" \
  --name "${app_secret_name}" \
  --query value -o tsv)

# Parse DB credentials
DB_HOST=$(echo "$DB_SECRET" | jq -r '.host')
DB_PORT=$(echo "$DB_SECRET" | jq -r '.port')
DB_NAME=$(echo "$DB_SECRET" | jq -r '.dbname')
DB_USER=$(echo "$DB_SECRET" | jq -r '.username')
DB_PASS=$(echo "$DB_SECRET" | jq -r '.password')

# ── Write environment file ─────────────────────────────────────────────────
mkdir -p /opt/sparc
cat > /opt/sparc/.env <<ENVEOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASS@$DB_HOST:$DB_PORT/$DB_NAME?sslmode=require
REDIS_URL=${redis_url}
ACTIVE_STORAGE_SERVICE=azure
AZURE_STORAGE_ACCOUNT_NAME=${storage_account_name}
AZURE_STORAGE_CONTAINER=${storage_container}
SPARC_APP_URL=${sparc_app_url}

$(echo "$APP_SECRET" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
ENVEOF

chmod 600 /opt/sparc/.env

# ── Write docker-compose file ──────────────────────────────────────────────
cat > /opt/sparc/docker-compose.yml <<'COMPOSEEOF'
${docker_compose_content}
COMPOSEEOF

# ── Start SPARC ─────────────────────────────────────────────────────────────
cd /opt/sparc
docker compose up -d

echo "=== SPARC bootstrap completed at $(date) ==="
