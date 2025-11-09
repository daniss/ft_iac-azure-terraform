variable "region" {
  type        = string
  default     = "Swiss"
  description = "Region name. Options: Swiss, EU-West, EU-North, US-East, US-West"
}

locals {
  region_map = {
    "Swiss"    = "switzerlandnorth"
    "EU-West"  = "westeurope"
    "EU-North" = "northeurope"
    "US-East"  = "eastus"
    "US-West"  = "westus"
  }
  
  resource_group_location = local.region_map[var.region]
}

variable "alert_email" {
  type = string
  description = "Email address to send alerts to."
}

variable "prefix" {
  type        = string
  default     = "win-vm-iis"
  description = "Prefix of the resource name"
}

variable "vm_size" {
  type        = string
  default     = "small"
  description = "VM size: small, medium, or large"
}

variable "db_size" {
  type        = string
  default     = "medium"
  description = "Database size: small, medium, or large"
}

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

variable "db_login" {
  type        = string
  description = "Administrator login for MySQL flexible server"
}

variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/id_rsa.pub"
  description = "Path to SSH public key file"
}

locals {
  vm_size_map = {
    "small"  = "Standard_B2s"
    "medium" = "Standard_B4ms"
    "large"  = "Standard_D4s_v3"
  }
  
  db_size_map = {
    "small"  = "B_Standard_B1ms"
    "medium" = "GP_Standard_D2ads_v5"
    "large"  = "GP_Standard_D4ads_v5"
  }

  public_key_ssh = file(var.ssh_public_key_path)
  
  app_vm_size = local.vm_size_map[var.vm_size]
  db_sku_name = local.db_size_map[var.db_size]
}