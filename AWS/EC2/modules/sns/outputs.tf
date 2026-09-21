output "topic_arn" {
  description = "ARN of the SNS alarm topic"
  value       = aws_sns_topic.alarms.arn
}

output "topic_name" {
  description = "Name of the SNS alarm topic"
  value       = aws_sns_topic.alarms.name
}
