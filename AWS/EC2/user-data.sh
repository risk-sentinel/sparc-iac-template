#!/bin/bash
set -euo pipefail

# ===========================================================================
# SPARC EC2 Bootstrap — User Data Script
# ===========================================================================
# This script runs on first boot to install Docker, mount EBS,
# pull SPARC + NGINX images, and start the application.
# Variables are injected by Terraform via templatefile().
# ===========================================================================

exec > >(tee /var/log/sparc-bootstrap.log) 2>&1
echo "=== SPARC bootstrap started at $(date) ==="

# ── Install Docker ──────────────────────────────────────────────────────────
dnf update -y
dnf install -y docker jq amazon-cloudwatch-agent
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# Install docker-compose plugin
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# ── Mount EBS Volume ────────────────────────────────────────────────────────
EBS_DEVICE="${ebs_device}"
MOUNT_PATH="${ebs_mount_path}"

# Wait for the EBS volume to be attached
while [ ! -e "$EBS_DEVICE" ]; do
  echo "Waiting for EBS volume at $EBS_DEVICE..."
  sleep 5
done

# Format if not already formatted
if ! blkid "$EBS_DEVICE"; then
  mkfs.xfs "$EBS_DEVICE"
fi

mkdir -p "$MOUNT_PATH"
mount "$EBS_DEVICE" "$MOUNT_PATH"
echo "$EBS_DEVICE $MOUNT_PATH xfs defaults,nofail 0 2" >> /etc/fstab

# Create app directories
mkdir -p "$MOUNT_PATH"/{uploads,logs}
chown -R 1000:1000 "$MOUNT_PATH"

# ── Authenticate to ECR ────────────────────────────────────────────────────
REGION="${aws_region}"
ECR_REGISTRY="${ecr_registry}"

if [ -n "$ECR_REGISTRY" ]; then
  aws ecr get-login-password --region "$REGION" \
    | docker login --username AWS --password-stdin "$ECR_REGISTRY"
fi

# ── Retrieve secrets ────────────────────────────────────────────────────────
DB_SECRET=$(aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "${db_secret_id}" \
  --query SecretString --output text)

APP_SECRET=$(aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "${app_secret_id}" \
  --query SecretString --output text)

# Parse DB credentials
DB_HOST=$(echo "$DB_SECRET" | jq -r '.host')
DB_PORT=$(echo "$DB_SECRET" | jq -r '.port')
DB_NAME=$(echo "$DB_SECRET" | jq -r '.dbname')
DB_USER=$(echo "$DB_SECRET" | jq -r '.username')
DB_PASS=$(echo "$DB_SECRET" | jq -r '.password')

# ── Write environment file ─────────────────────────────────────────────────
cat > /opt/sparc/.env <<ENVEOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASS@$DB_HOST:$DB_PORT/$DB_NAME?sslmode=require
REDIS_URL=${redis_url}
ACTIVE_STORAGE_SERVICE=amazon
AWS_BUCKET=${s3_bucket}
AWS_REGION=$REGION
SPARC_APP_URL=${sparc_app_url}

$(echo "$APP_SECRET" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
ENVEOF

chmod 600 /opt/sparc/.env

# ── Write docker-compose file ──────────────────────────────────────────────
mkdir -p /opt/sparc
cat > /opt/sparc/docker-compose.yml <<'COMPOSEEOF'
${docker_compose_content}
COMPOSEEOF

# ── Start SPARC ─────────────────────────────────────────────────────────────
cd /opt/sparc
docker compose up -d

# ── Configure CloudWatch Agent ──────────────────────────────────────────────
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<'CWEOF'
{
  "agent": { "run_as_user": "root" },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/sparc-bootstrap.log",
            "log_group_name": "/ec2/${project_name}-${environment}/bootstrap",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "${ebs_mount_path}/logs/*.log",
            "log_group_name": "/ec2/${project_name}-${environment}/app",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "${project_name}-${environment}/EC2",
    "metrics_collected": {
      "disk": { "measurement": ["used_percent"], "resources": ["*"] },
      "mem": { "measurement": ["mem_used_percent"] }
    }
  }
}
CWEOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json -s

echo "=== SPARC bootstrap completed at $(date) ==="
