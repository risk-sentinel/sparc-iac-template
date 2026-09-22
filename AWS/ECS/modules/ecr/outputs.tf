output "repository_url" {
  description = "Full URL of the ECR repository (use as sparc_image base)"
  value       = aws_ecr_repository.main.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.main.arn
}

output "repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.main.name
}

output "nginx_repository_url" {
  description = "Full URL of the NGINX ECR repository"
  value       = aws_ecr_repository.nginx.repository_url
}

output "nginx_repository_name" {
  description = "Name of the NGINX ECR repository"
  value       = aws_ecr_repository.nginx.name
}

output "vulcan_repository_url" {
  description = "Full URL of the vulcan ECR repository (org-adopted standalone image; #387)"
  value       = aws_ecr_repository.vulcan.repository_url
}

output "heimdall2_repository_url" {
  description = "Full URL of the heimdall2 ECR repository (org-adopted standalone image, now terraform-managed; #387)"
  value       = aws_ecr_repository.heimdall2.repository_url
}

output "ci_runner_repository_url" {
  description = "Full URL of the sparc-ci-runner ECR repository (container-build-sign publishes here; #438/#461)"
  value       = aws_ecr_repository.ci_runner.repository_url
}

output "auditor_repository_url" {
  description = "Full URL of the sparc-auditor ECR repository (container-build-sign publishes here; #438)"
  value       = aws_ecr_repository.auditor.repository_url
}
