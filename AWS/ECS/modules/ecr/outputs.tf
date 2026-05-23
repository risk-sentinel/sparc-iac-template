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
