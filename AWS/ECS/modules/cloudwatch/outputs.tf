output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "vpc_flow_log_group_name" {
  description = "Name of the VPC flow log CloudWatch log group"
  value       = aws_cloudwatch_log_group.vpc_flow.name
}

output "alarm_names" {
  description = "List of all CloudWatch alarm names"
  value = concat(
    [
      aws_cloudwatch_metric_alarm.ecs_cpu.alarm_name,
      aws_cloudwatch_metric_alarm.ecs_memory.alarm_name,
      aws_cloudwatch_metric_alarm.alb_5xx.alarm_name,
      aws_cloudwatch_metric_alarm.alb_latency.alarm_name,
      aws_cloudwatch_metric_alarm.alb_unhealthy.alarm_name,
      aws_cloudwatch_metric_alarm.rds_cpu.alarm_name,
      aws_cloudwatch_metric_alarm.rds_storage.alarm_name,
      aws_cloudwatch_metric_alarm.rds_connections.alarm_name,
      aws_cloudwatch_metric_alarm.nginx_5xx_rate.alarm_name,
      aws_cloudwatch_metric_alarm.rails_error_rate.alarm_name,
    ],
    [for a in aws_cloudwatch_metric_alarm.redis_cpu : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.redis_memory : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.app_secret_access : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.app_secret_modify : a.alarm_name],
  )
}

output "cloudtrail_log_group_arn" {
  description = "ARN of the CloudTrail CloudWatch log group (used by Lambda module for permission)"
  value       = try(aws_cloudwatch_log_group.cloudtrail[0].arn, "")
}
