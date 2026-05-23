output "artifacts_bucket_id" {
  description = "Security artifacts S3 bucket ID"
  value       = aws_s3_bucket.artifacts.id
}

output "artifacts_bucket_arn" {
  description = "Security artifacts S3 bucket ARN"
  value       = aws_s3_bucket.artifacts.arn
}

output "alb_access_logs_prefix" {
  description = "S3 prefix for ALB access logs"
  value       = "alb-logs"
}

