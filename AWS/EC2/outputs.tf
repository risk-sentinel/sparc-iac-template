output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "app_fqdn" {
  description = "FQDN of the application (if Route 53 configured)"
  value       = length(module.route53) > 0 ? module.route53[0].fqdn : null
}

output "app_url" {
  description = "SPARC application URL"
  value       = local.sparc_app_url
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = module.ec2_instance.instance_id
}

output "instance_private_ip" {
  description = "EC2 instance private IP"
  value       = module.ec2_instance.private_ip
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_endpoint
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.elasticache.redis_endpoint
}

output "s3_bucket_name" {
  description = "S3 bucket name for SPARC uploads"
  value       = module.s3.bucket_name
}

output "ebs_volume_id" {
  description = "EBS data volume ID"
  value       = module.ebs.volume_id
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for DB credentials"
  value       = module.rds.db_secret_arn
}

output "app_secret_arn" {
  description = "Secrets Manager ARN for SPARC app secrets"
  value       = module.secrets.app_secret_arn
}

output "sns_topic_arn" {
  description = "SNS alarm notifications topic ARN"
  value       = module.sns.topic_arn
}

output "cloudwatch_dashboard_name" {
  description = "CloudWatch monitoring dashboard name"
  value       = module.cloudwatch.dashboard_name
}

output "ssm_connect_command" {
  description = "Command to connect via SSM Session Manager"
  value       = "aws ssm start-session --target ${module.ec2_instance.instance_id} --region ${var.aws_region}"
}
