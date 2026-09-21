output "detector_id" {
  description = "GuardDuty detector ID"
  value       = aws_guardduty_detector.main.id
}

output "detector_arn" {
  description = "GuardDuty detector ARN"
  value       = aws_guardduty_detector.main.arn
}

output "sns_topic_arn" {
  description = "SNS topic ARN for GuardDuty finding notifications"
  value       = aws_sns_topic.findings.arn
}
