variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "availability_zones" {
  type = list(string)
}

variable "container_port" {
  type = number
}

variable "hibernate" {
  description = "Hibernate mode: skip NAT gateway to save cost"
  type        = bool
  default     = false
}

variable "enable_redis" {
  description = "Create Redis security group"
  type        = bool
  default     = true
}
