variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "certificate_arn" {
  type = string
}

variable "health_check_path" {
  type = string
}

variable "app_port" {
  description = "Application port on the EC2 instance"
  type        = number
}

variable "instance_id" {
  description = "EC2 instance ID to register with the target group"
  type        = string
}
