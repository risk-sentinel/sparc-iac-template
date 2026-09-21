output "asg_name" {
  description = "Auto Scaling Group name — scale 0<->1 on demand; the 9pm self-off timer targets this."
  value       = aws_autoscaling_group.rhel9.name
}

output "asg_arn" {
  description = "ASG ARN"
  value       = aws_autoscaling_group.rhel9.arn
}

output "security_group_id" {
  description = "Test-instance security group ID (egress-only)"
  value       = aws_security_group.rhel9.id
}
