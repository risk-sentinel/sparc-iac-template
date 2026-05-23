locals {
  name_prefix = "${var.project_name}-${var.environment}"
  sns_actions = [var.sns_topic_arn]
}

# ===========================================================================
# VPC Flow Logs → CloudWatch
# ===========================================================================

resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/vpc/${local.name_prefix}/flow-logs"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "${local.name_prefix}-vpc-flow-logs"
  }
}

resource "aws_flow_log" "main" {
  vpc_id                   = var.vpc_id
  traffic_type             = "ALL"
  log_destination          = aws_cloudwatch_log_group.vpc_flow.arn
  log_destination_type     = "cloud-watch-logs"
  iam_role_arn             = var.flow_log_role_arn
  max_aggregation_interval = 60

  tags = {
    Name = "${local.name_prefix}-vpc-flow-log"
  }
}

# ===========================================================================
# Log Metric Filters — extract error metrics from application logs
# ===========================================================================

resource "aws_cloudwatch_log_metric_filter" "nginx_5xx" {
  name           = "${local.name_prefix}-nginx-5xx"
  log_group_name = var.ecs_log_group_name
  pattern        = "[ip, user, timestamp, request, status_code = 5*, ...]"

  metric_transformation {
    name      = "Nginx5xxCount"
    namespace = "${local.name_prefix}/Application"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "rails_error" {
  name           = "${local.name_prefix}-rails-error"
  log_group_name = var.ecs_log_group_name
  pattern        = "\"ERROR\""

  metric_transformation {
    name      = "RailsErrorCount"
    namespace = "${local.name_prefix}/Application"
    value     = "1"
  }
}

# ===========================================================================
# ECS Alarms
# ===========================================================================

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${local.name_prefix}-ecs-cpu-high"
  alarm_description   = "ECS service CPU utilization above ${var.ecs_cpu_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = var.ecs_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions             = local.sns_actions
  ok_actions                = local.sns_actions
  insufficient_data_actions = local.sns_actions

  tags = {
    Name = "${local.name_prefix}-ecs-cpu-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  alarm_name          = "${local.name_prefix}-ecs-memory-high"
  alarm_description   = "ECS service memory utilization above ${var.ecs_memory_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = var.ecs_memory_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions             = local.sns_actions
  ok_actions                = local.sns_actions
  insufficient_data_actions = local.sns_actions

  tags = {
    Name = "${local.name_prefix}-ecs-memory-high"
  }
}

# ===========================================================================
# ALB Alarms
# ===========================================================================

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name_prefix}-alb-5xx"
  alarm_description   = "ALB 5xx errors above ${var.alb_5xx_threshold} in 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions             = local.sns_actions
  ok_actions                = local.sns_actions
  insufficient_data_actions = local.sns_actions

  tags = {
    Name = "${local.name_prefix}-alb-5xx"
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "${local.name_prefix}-alb-latency-high"
  alarm_description   = "ALB target response time above ${var.alb_latency_threshold}s"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = var.alb_latency_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions             = local.sns_actions
  ok_actions                = local.sns_actions
  insufficient_data_actions = local.sns_actions

  tags = {
    Name = "${local.name_prefix}-alb-latency-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy" {
  alarm_name          = "${local.name_prefix}-alb-unhealthy-targets"
  alarm_description   = "ALB has unhealthy targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions             = local.sns_actions
  ok_actions                = local.sns_actions
  insufficient_data_actions = local.sns_actions

  tags = {
    Name = "${local.name_prefix}-alb-unhealthy-targets"
  }
}

# ===========================================================================
# RDS Alarms
# ===========================================================================

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${local.name_prefix}-rds-cpu-high"
  alarm_description   = "RDS CPU utilization above ${var.rds_cpu_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.rds_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }

  alarm_actions             = local.sns_actions
  ok_actions                = local.sns_actions
  insufficient_data_actions = local.sns_actions

  tags = {
    Name = "${local.name_prefix}-rds-cpu-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${local.name_prefix}-rds-storage-low"
  alarm_description   = "RDS free storage below threshold"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.rds_free_storage_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }

  alarm_actions             = local.sns_actions
  ok_actions                = local.sns_actions
  insufficient_data_actions = local.sns_actions

  tags = {
    Name = "${local.name_prefix}-rds-storage-low"
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${local.name_prefix}-rds-connections-high"
  alarm_description   = "RDS database connections above 80% of max"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }

  alarm_actions             = local.sns_actions
  ok_actions                = local.sns_actions
  insufficient_data_actions = local.sns_actions

  tags = {
    Name = "${local.name_prefix}-rds-connections-high"
  }
}

# ===========================================================================
# ElastiCache Alarms
# ===========================================================================

resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  count               = var.redis_replication_group_id != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-redis-cpu-high"
  alarm_description   = "Redis engine CPU utilization above ${var.redis_cpu_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "EngineCPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = var.redis_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = var.redis_replication_group_id
  }

  alarm_actions             = local.sns_actions
  ok_actions                = local.sns_actions
  insufficient_data_actions = local.sns_actions

  tags = {
    Name = "${local.name_prefix}-redis-cpu-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  count               = var.redis_replication_group_id != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-redis-memory-high"
  alarm_description   = "Redis database memory usage above ${var.redis_memory_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = var.redis_memory_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = var.redis_replication_group_id
  }

  alarm_actions             = local.sns_actions
  ok_actions                = local.sns_actions
  insufficient_data_actions = local.sns_actions

  tags = {
    Name = "${local.name_prefix}-redis-memory-high"
  }
}

# ===========================================================================
# Application Error Alarms (from log metric filters)
# ===========================================================================

resource "aws_cloudwatch_metric_alarm" "nginx_5xx_rate" {
  alarm_name          = "${local.name_prefix}-nginx-5xx-rate"
  alarm_description   = "NGINX 5xx error rate elevated"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Nginx5xxCount"
  namespace           = "${local.name_prefix}/Application"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  alarm_actions             = local.sns_actions
  ok_actions                = local.sns_actions
  insufficient_data_actions = local.sns_actions

  tags = {
    Name = "${local.name_prefix}-nginx-5xx-rate"
  }
}

resource "aws_cloudwatch_metric_alarm" "rails_error_rate" {
  alarm_name          = "${local.name_prefix}-rails-error-rate"
  alarm_description   = "Rails ERROR log rate elevated"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RailsErrorCount"
  namespace           = "${local.name_prefix}/Application"
  period              = 300
  statistic           = "Sum"
  threshold           = 20
  treat_missing_data  = "notBreaching"

  alarm_actions             = local.sns_actions
  ok_actions                = local.sns_actions
  insufficient_data_actions = local.sns_actions

  tags = {
    Name = "${local.name_prefix}-rails-error-rate"
  }
}

# ===========================================================================
# CloudTrail + App Secret Access Alarm
# ===========================================================================

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  count             = var.enable_app_secret_alarm ? 1 : 0
  name              = "/cloudtrail/${local.name_prefix}"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "${local.name_prefix}-cloudtrail-logs"
  }
}

resource "aws_cloudtrail" "main" {
  count                         = var.enable_app_secret_alarm ? 1 : 0
  name                          = "${local.name_prefix}-trail"
  s3_bucket_name                = var.s3_bucket_id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
  cloud_watch_logs_role_arn     = var.cloudtrail_role_arn
  kms_key_id                    = var.kms_key_arn
  # SNS notification omitted — CloudTrail cannot use the AWS-managed SNS key
  # (alias/aws/sns) and requires a CMK with explicit CloudTrail permissions.
  # App secret access notification is handled by CloudWatch metric filter
  # → alarm → SNS instead. CKV_AWS_252 baselined.

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3"]
    }
  }

  tags = {
    Name = "${local.name_prefix}-cloudtrail"
  }
}

# Two metric filters emit to the same metric. Split by identity type
# because sessionContext only exists for AssumedRole events — a single
# filter can't safely reference it for all identity types.

# Filter 1: Root + IAMUser (console, CLI, API)
resource "aws_cloudwatch_log_metric_filter" "app_secret_access" {
  count          = var.enable_app_secret_alarm ? 1 : 0
  name           = "${local.name_prefix}-app-secret-access"
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name

  pattern = "{ ($.eventName = \"GetSecretValue\") && ($.requestParameters.secretId = \"*app-secrets*\") && (($.userIdentity.type = \"IAMUser\") || ($.userIdentity.type = \"Root\")) }"

  metric_transformation {
    name      = "AppSecretAccessCount"
    namespace = "${local.name_prefix}/Security"
    value     = "1"
  }
}

# Filter 2: AssumedRole EXCEPT the CI role (covers SSO users).
# sessionContext.sessionIssuer.userName always exists for AssumedRole.
resource "aws_cloudwatch_log_metric_filter" "app_secret_access_sso" {
  count          = var.enable_app_secret_alarm ? 1 : 0
  name           = "${local.name_prefix}-app-secret-access-sso"
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name

  pattern = "{ ($.eventName = \"GetSecretValue\") && ($.requestParameters.secretId = \"*app-secrets*\") && ($.userIdentity.type = \"AssumedRole\") && ($.userIdentity.sessionContext.sessionIssuer.userName != \"sparc-iac-github-actions\") }"

  metric_transformation {
    name      = "AppSecretAccessCount"
    namespace = "${local.name_prefix}/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "app_secret_access" {
  count               = var.enable_app_secret_alarm ? 1 : 0
  alarm_name          = "${local.name_prefix}-app-secret-accessed"
  alarm_description   = "App secrets (sparc-prod/app-secrets) was accessed — verify authorized usage. Auto-resets ~60s after last access."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "AppSecretAccessCount"
  namespace           = "${local.name_prefix}/Security"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  # ALARM + OK notifications. During an active grant window (repeated
  # access within 60s) the alarm stays in ALARM — CloudWatch only
  # notifies on state change, so no email spam. When 60s passes with
  # no access, the alarm resets to OK and fires the OK email.
  # No insufficient_data_actions (noise for sparse security metrics).
  alarm_actions = local.sns_actions
  ok_actions    = local.sns_actions

  tags = {
    Name = "${local.name_prefix}-app-secret-accessed"
  }
}

# ---------------------------------------------------------------------------
# App Secret MODIFICATION Alarm (#161)
#
# Mirrors the access alarm pattern above but for mutating operations.
# Two metric filters (IAMUser/Root + AssumedRole-minus-CI) emit to the
# same metric so a single alarm covers both identity types.
# ---------------------------------------------------------------------------

locals {
  secret_modify_events = "\"PutSecretValue\" || $.eventName = \"UpdateSecret\" || $.eventName = \"UpdateSecretVersionStage\" || $.eventName = \"DeleteSecret\" || $.eventName = \"RestoreSecret\" || $.eventName = \"RotateSecret\" || $.eventName = \"TagResource\" || $.eventName = \"UntagResource\" || $.eventName = \"PutResourcePolicy\" || $.eventName = \"DeleteResourcePolicy\""
}

# Filter 1: Root + IAMUser — modification events
resource "aws_cloudwatch_log_metric_filter" "app_secret_modify" {
  count          = var.enable_app_secret_alarm ? 1 : 0
  name           = "${local.name_prefix}-app-secret-modify"
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name

  pattern = "{ ($.eventName = ${local.secret_modify_events}) && ($.requestParameters.secretId = \"*app-secrets*\") && (($.userIdentity.type = \"IAMUser\") || ($.userIdentity.type = \"Root\")) }"

  metric_transformation {
    name      = "AppSecretModificationCount"
    namespace = "${local.name_prefix}/Security"
    value     = "1"
  }
}

# Filter 2: AssumedRole EXCEPT the CI role — modification events
resource "aws_cloudwatch_log_metric_filter" "app_secret_modify_sso" {
  count          = var.enable_app_secret_alarm ? 1 : 0
  name           = "${local.name_prefix}-app-secret-modify-sso"
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name

  pattern = "{ ($.eventName = ${local.secret_modify_events}) && ($.requestParameters.secretId = \"*app-secrets*\") && ($.userIdentity.type = \"AssumedRole\") && ($.userIdentity.sessionContext.sessionIssuer.userName != \"sparc-iac-github-actions\") }"

  metric_transformation {
    name      = "AppSecretModificationCount"
    namespace = "${local.name_prefix}/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "app_secret_modify" {
  count               = var.enable_app_secret_alarm ? 1 : 0
  alarm_name          = "${local.name_prefix}-app-secret-modified"
  alarm_description   = "App secrets (sparc-prod/app-secrets) was modified (PutSecretValue, UpdateSecret, DeleteSecret, etc.) — verify authorized change. Auto-resets ~60s after last modification."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "AppSecretModificationCount"
  namespace           = "${local.name_prefix}/Security"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = local.sns_actions
  ok_actions    = local.sns_actions

  tags = {
    Name = "${local.name_prefix}-app-secret-modified"
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Logs Subscription Filter — Secret Alert Lambda (#156)
#
# CloudTrail → EventBridge delivery is confirmed non-functional for this
# account (zero MatchedEvents for 7+ days — see issue #156). The
# EventBridge rules below are kept as-is (zero cost idle) but we bypass
# them with a CloudWatch Logs subscription filter → Lambda → SNS path
# that reliably delivers identity-enriched notifications for both access
# and modification events on app-secrets.
#
# The Lambda function itself lives in modules/lambda/ (shared Lambda
# module). This filter connects the CloudTrail log group (owned by this
# module) to that Lambda.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_subscription_filter" "secret_alert" {
  count           = var.enable_app_secret_alarm ? 1 : 0
  name            = "${local.name_prefix}-secret-alert"
  log_group_name  = aws_cloudwatch_log_group.cloudtrail[0].name
  destination_arn = var.secret_alert_lambda_arn
  filter_pattern  = "{ ($.eventSource = \"secretsmanager.amazonaws.com\") && ($.requestParameters.secretId = \"*app-secrets*\") }"
}

# ---------------------------------------------------------------------------
# EventBridge — App Secret Access with Identity
#
# NOTE: CloudTrail → EventBridge delivery is confirmed non-functional for
# this account (zero MatchedEvents for 7+ days — see issue #156). These
# rules are retained at zero cost and will activate if/when the delivery
# issue is resolved. In the meantime, the Lambda subscription filter
# above provides identical identity-enriched notifications.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "app_secret_access" {
  count       = var.enable_app_secret_alarm ? 1 : 0
  name        = "${local.name_prefix}-app-secret-access"
  description = "Notify when app-secrets is accessed (includes accessor identity)"

  # Exclude Terraform CI by userAgent prefix. The userAgent field always
  # exists in CloudTrail events (unlike sessionContext which is role-only).
  # Terraform's agent is "APN/1.0 HashiCorp/1.0 Terraform/...".
  event_pattern = jsonencode({
    source      = ["aws.secretsmanager"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["secretsmanager.amazonaws.com"]
      eventName   = ["GetSecretValue"]
      requestParameters = {
        secretId = [{ "wildcard" : "*app-secrets*" }]
      }
      userAgent = [{ "anything-but" : { "prefix" : "APN/1.0 HashiCorp" } }]
    }
  })

  tags = {
    Name = "${local.name_prefix}-app-secret-access"
  }
}

resource "aws_cloudwatch_event_target" "app_secret_sns" {
  count     = var.enable_app_secret_alarm ? 1 : 0
  rule      = aws_cloudwatch_event_rule.app_secret_access[0].name
  target_id = "app-secret-to-sns"
  arn       = var.sns_topic_arn

  input_transformer {
    input_paths = {
      account   = "$.account"
      time      = "$.time"
      region    = "$.region"
      principal = "$.detail.userIdentity.arn"
      sourceIP  = "$.detail.sourceIpAddress"
      secretId  = "$.detail.requestParameters.secretId"
    }

    input_template = "\"SECURITY ALERT: App secret accessed.\\n\\nWho: <principal>\\nSource IP: <sourceIP>\\nSecret: <secretId>\\nTime: <time>\\nAccount: <account>\\nRegion: <region>\\n\\nVerify this was authorized usage.\""
  }
}

# ===========================================================================
# CloudWatch Dashboard
# ===========================================================================

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ${upper(var.project_name)} ${upper(var.environment)} — Infrastructure Dashboard"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "ECS CPU & Memory"
          region = var.aws_region
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name, { label = "CPU %" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name, { label = "Memory %" }]
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count & Latency"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { label = "Requests", stat = "Sum" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { label = "Latency (s)", stat = "Average", yAxis = "right" }]
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "ALB HTTP Errors"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "5xx", stat = "Sum", color = "#d62728" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "4xx", stat = "Sum", color = "#ff7f0e" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "2xx", stat = "Sum", color = "#2ca02c" }]
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "RDS Performance"
          region = var.aws_region
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id, { label = "CPU %", stat = "Average" }],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_id, { label = "Connections", stat = "Average", yAxis = "right" }]
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "Application Errors (from logs)"
          region = var.aws_region
          metrics = [
            ["${local.name_prefix}/Application", "Nginx5xxCount", { label = "NGINX 5xx", stat = "Sum", color = "#d62728" }],
            ["${local.name_prefix}/Application", "RailsErrorCount", { label = "Rails ERROR", stat = "Sum", color = "#ff7f0e" }]
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "ALB Healthy / Unhealthy Targets"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { label = "Healthy", stat = "Average", color = "#2ca02c" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { label = "Unhealthy", stat = "Average", color = "#d62728" }]
          ]
          period = 300
          view   = "timeSeries"
        }
      }
    ]
  })
}
