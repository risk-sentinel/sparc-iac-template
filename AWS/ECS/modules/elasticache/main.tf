locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Random password for Redis AUTH
# ---------------------------------------------------------------------------

resource "random_password" "redis_auth" {
  length           = 32
  special          = true
  override_special = "!&#$^<>-"
}

# ---------------------------------------------------------------------------
# Subnet Group
# ---------------------------------------------------------------------------

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.name_prefix}-redis"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${local.name_prefix}-redis-subnet-group"
  }
}

# ---------------------------------------------------------------------------
# Parameter Group
# ---------------------------------------------------------------------------

resource "aws_elasticache_parameter_group" "main" {
  name   = "${local.name_prefix}-redis"
  family = var.parameter_group_family

  tags = {
    Name = "${local.name_prefix}-redis-params"
  }
}

# ---------------------------------------------------------------------------
# Redis Replication Group (supports encryption)
# ---------------------------------------------------------------------------

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${local.name_prefix}-redis"
  description          = "${local.name_prefix} Redis for SPARC"
  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_nodes
  parameter_group_name = aws_elasticache_parameter_group.main.name
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [var.redis_sg_id]
  port                 = 6379

  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn
  automatic_failover_enabled = var.num_cache_nodes > 1
  auth_token                 = random_password.redis_auth.result

  engine_version = var.engine_version

  tags = {
    Name = "${local.name_prefix}-redis"
  }
}
