variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "alert_emails" {
  description = "List of email addresses for alert notifications"
  type        = list(string)
}
