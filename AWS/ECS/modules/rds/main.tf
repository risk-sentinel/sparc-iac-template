locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Random password (never stored in tfvars)
# ---------------------------------------------------------------------------

resource "random_password" "db" {
  length  = 32
  special = false
}

# ---------------------------------------------------------------------------
# DB Subnet Group
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

# ---------------------------------------------------------------------------
# RDS PostgreSQL Instance
# ---------------------------------------------------------------------------

resource "aws_db_instance" "main" {
  identifier     = "${local.name_prefix}-db"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]

  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
  skip_final_snapshot     = var.db_skip_final_snapshot

  final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${local.name_prefix}-db-final-snapshot"

  auto_minor_version_upgrade          = true
  deletion_protection                 = var.db_deletion_protection
  performance_insights_enabled        = true
  performance_insights_kms_key_id     = var.kms_key_arn
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]
  monitoring_interval                 = 60
  monitoring_role_arn                 = aws_iam_role.rds_enhanced_monitoring.arn

  tags = {
    Name = "${local.name_prefix}-db"
  }
}

# ---------------------------------------------------------------------------
# IAM Role for RDS Enhanced Monitoring
# ---------------------------------------------------------------------------

resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "${local.name_prefix}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-rds-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ---------------------------------------------------------------------------
# Secrets Manager — store DB credentials as JSON
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "db" {
  name = "${local.name_prefix}/db-credentials"

  tags = {
    Name = "${local.name_prefix}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = var.db_name
  })
}

# ---------------------------------------------------------------------------
# Secrets Manager Rotation — AWS-managed Lambda for PostgreSQL
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret_rotation" "db" {
  count               = var.enable_secret_rotation ? 1 : 0
  secret_id           = aws_secretsmanager_secret.db.id
  rotation_lambda_arn = aws_serverlessapplicationrepository_cloudformation_stack.rotation[0].outputs["RotationLambdaARN"]

  rotation_rules {
    automatically_after_days = var.rotation_schedule_days
  }

  depends_on = [aws_db_instance.main]
}

# Deploy the AWS-managed rotation Lambda from SAR
resource "aws_serverlessapplicationrepository_cloudformation_stack" "rotation" {
  count          = var.enable_secret_rotation ? 1 : 0
  name           = "${local.name_prefix}-db-rotation"
  application_id = "arn:aws:serverlessrepo:us-east-1:297356227824:applications/SecretsManagerRDSPostgreSQLRotationSingleUser"

  capabilities = ["CAPABILITY_IAM", "CAPABILITY_RESOURCE_POLICY"]

  parameters = {
    endpoint            = "https://secretsmanager.${data.aws_region.current.name}.amazonaws.com"
    functionName        = "${local.name_prefix}-db-rotation"
    vpcSubnetIds        = join(",", var.private_subnet_ids)
    vpcSecurityGroupIds = var.rds_sg_id
  }
}

# ---------------------------------------------------------------------------
# Dead Letter Queue for Rotation Lambda
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "rotation_dlq" {
  count                     = var.enable_secret_rotation ? 1 : 0
  name                      = "${local.name_prefix}-db-rotation-dlq"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = var.kms_key_arn

  tags = {
    Name = "${local.name_prefix}-db-rotation-dlq"
  }
}

# Look up the SAR-deployed rotation Lambda to get its execution role.
# Required so we can attach an inline policy granting sqs:SendMessage on the DLQ.
data "aws_lambda_function" "rotation" {
  count         = var.enable_secret_rotation ? 1 : 0
  function_name = "${local.name_prefix}-db-rotation"

  depends_on = [aws_serverlessapplicationrepository_cloudformation_stack.rotation]
}

# Grant the rotation Lambda's execution role permission to send messages to the DLQ.
# The role is created by the SAR CloudFormation stack, not directly by Terraform.
resource "aws_iam_role_policy" "rotation_dlq_send" {
  count = var.enable_secret_rotation ? 1 : 0
  name  = "${local.name_prefix}-db-rotation-dlq-send"
  role  = replace(data.aws_lambda_function.rotation[0].role, "/^.*role\\//", "")

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.rotation_dlq[0].arn
    }]
  })
}

resource "aws_lambda_function_event_invoke_config" "rotation_dlq" {
  count         = var.enable_secret_rotation ? 1 : 0
  function_name = aws_serverlessapplicationrepository_cloudformation_stack.rotation[0].outputs["RotationLambdaARN"]

  destination_config {
    on_failure {
      destination = aws_sqs_queue.rotation_dlq[0].arn
    }
  }

  depends_on = [aws_iam_role_policy.rotation_dlq_send]
}

# ---------------------------------------------------------------------------
# RDS Proxy (conditional: var.enable_rds_proxy)
# ---------------------------------------------------------------------------

resource "aws_iam_role" "rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0
  name  = "${local.name_prefix}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "rds.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${local.name_prefix}-rds-proxy-role"
  }
}

resource "aws_iam_role_policy" "rds_proxy_secrets" {
  count = var.enable_rds_proxy ? 1 : 0
  name  = "${local.name_prefix}-rds-proxy-secrets"
  role  = aws_iam_role.rds_proxy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["secretsmanager:GetSecretValue"]
        Effect   = "Allow"
        Resource = [aws_secretsmanager_secret.db.arn]
      },
      {
        Action   = ["kms:Decrypt"]
        Effect   = "Allow"
        Resource = ["*"]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })
}

data "aws_region" "current" {}

resource "aws_security_group" "rds_proxy" {
  count       = var.enable_rds_proxy ? 1 : 0
  name        = "${local.name_prefix}-rds-proxy-sg"
  description = "Allow ECS to RDS Proxy, Proxy to RDS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.ecs_sg_id]
  }

  egress {
    description     = "PostgreSQL to RDS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.rds_sg_id]
  }

  tags = {
    Name = "${local.name_prefix}-rds-proxy-sg"
  }
}

resource "aws_db_proxy" "main" {
  count               = var.enable_rds_proxy ? 1 : 0
  name                = "${local.name_prefix}-proxy"
  engine_family       = "POSTGRESQL"
  require_tls         = true
  role_arn            = aws_iam_role.rds_proxy[0].arn
  idle_client_timeout = 1800

  vpc_subnet_ids         = var.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.rds_proxy[0].id]

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "REQUIRED"
    secret_arn  = aws_secretsmanager_secret.db.arn
  }

  tags = {
    Name = "${local.name_prefix}-rds-proxy"
  }
}

resource "aws_db_proxy_default_target_group" "main" {
  count         = var.enable_rds_proxy ? 1 : 0
  db_proxy_name = aws_db_proxy.main[0].name

  connection_pool_config {
    max_connections_percent      = var.rds_proxy_max_connections_percent
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "main" {
  count                  = var.enable_rds_proxy ? 1 : 0
  db_proxy_name          = aws_db_proxy.main[0].name
  target_group_name      = aws_db_proxy_default_target_group.main[0].name
  db_instance_identifier = aws_db_instance.main.identifier
}
