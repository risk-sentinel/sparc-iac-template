# ---------------------------------------------------------------------------
# Managed Rules — 10 high-value security checks
# ---------------------------------------------------------------------------

locals {
  managed_rules = var.enable_aws_config ? {
    encrypted-volumes = {
      source = "ENCRYPTED_VOLUMES"
      nist   = "SC-28"
      input  = {}
    }
    rds-storage-encrypted = {
      source = "RDS_STORAGE_ENCRYPTED"
      nist   = "SC-28"
      input  = {}
    }
    s3-bucket-ssl-requests-only = {
      source = "S3_BUCKET_SSL_REQUESTS_ONLY"
      nist   = "SC-8"
      input  = {}
    }
    iam-user-no-policies-check = {
      source = "IAM_USER_NO_POLICIES_CHECK"
      nist   = "AC-6"
      input  = {}
    }
    vpc-flow-logs-enabled = {
      source = "VPC_FLOW_LOGS_ENABLED"
      nist   = "AU-2"
      input  = {}
    }
    cloud-trail-enabled = {
      source = "CLOUD_TRAIL_ENABLED"
      nist   = "AU-2"
      input  = {}
    }
    restricted-ssh = {
      source = "INCOMING_SSH_DISABLED"
      nist   = "AC-17"
      input  = {}
    }
    rds-multi-az-support = {
      source = "RDS_MULTI_AZ_SUPPORT"
      nist   = "CP-9"
      input  = {}
    }
    secretsmanager-rotation-enabled-check = {
      source = "SECRETSMANAGER_ROTATION_ENABLED_CHECK"
      nist   = "IA-5"
      input  = {}
    }
  } : {}
}

resource "aws_config_config_rule" "managed" {
  for_each = local.managed_rules

  name = "${local.name_prefix}-${each.key}"

  source {
    owner             = "AWS"
    source_identifier = each.value.source
  }

  tags = {
    Name        = "${local.name_prefix}-${each.key}"
    NistControl = each.value.nist
  }

  depends_on = [aws_config_configuration_recorder.main]
}
