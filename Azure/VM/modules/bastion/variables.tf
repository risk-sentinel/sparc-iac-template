variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev/staging/prod)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create the Bastion host in"
  type        = string
}

variable "bastion_subnet_id" {
  description = "ID of the AzureBastionSubnet (created in the networking module when enable_bastion is set)"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace resource ID for Bastion audit/session logs"
  type        = string
}
