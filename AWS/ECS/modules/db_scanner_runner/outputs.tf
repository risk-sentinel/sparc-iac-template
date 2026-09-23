output "asg_name" {
  description = "Auto Scaling Group name — sparc-validate's orchestration job sets desired-capacity on this ASG to scale runners up and down."
  value       = aws_autoscaling_group.runner.name
}

output "asg_arn" {
  description = "ASG ARN for orchestrator policy ref (exposed for completeness; sparc-validate only needs the name)"
  value       = aws_autoscaling_group.runner.arn
}

output "app_key_secret_arn" {
  description = "Secrets Manager ARN of the runner GitHub App credentials JSON ({app_id, installation_id, private_key}). Populated out-of-band post-apply per the runbook (#190)."
  value       = aws_secretsmanager_secret.runner_app_key.arn
}

output "app_key_secret_name" {
  description = "Secrets Manager secret name (friendly handle for the runbook / AWS console)"
  value       = aws_secretsmanager_secret.runner_app_key.name
}

output "runner_labels" {
  description = "Labels applied to the ephemeral runner. sparc-validate's scan job must include these in runs-on."
  value       = var.runner_labels
}

output "runner_sg_id" {
  description = "Runner security group ID (exposed for debugging; generally not needed externally)"
  value       = aws_security_group.runner.id
}
