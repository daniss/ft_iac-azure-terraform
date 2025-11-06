variable "resource_group_location" {
  default     = "switzerlandnorth"
  description = "Location of the resource group."
}

variable "prefix" {
  type        = string
  default     = "win-vm-iis"
  description = "Prefix of the resource name"
}

variable "app_vm_size" {
  type        = string
  default     = "Standard_B2s"
  description = "Size of the application VM."
}