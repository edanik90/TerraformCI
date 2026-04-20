# ============================================================
# variables.tf
# ============================================================

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
}

#variable "resource_group_name" {
#  description = "Name of the resource group"
#  type        = string
#  default     = "rg-windows-vm"
#}

/* variable "vm_name" {
  description = "Name of the Windows Server VM"
  type        = string
  default     = "vm-win-server"
} */

#variable "bastion_name" {
#  description = "Name of the Bastion Host"
#  type        = string
#  default     = "bastion-host"
#}

variable "vm_size" {
  description = "Size/SKU of the VM"
  type        = string
  default     = "Standard_DC1s_v3"
}

variable "admin_username" {
  description = "Administrator username for the VM"
  type        = string
  default     = "vmadmin"
}

variable "admin_password" {
  description = "Administrator password for the VM — set via TFC sensitive variable or $env:TF_VAR_admin_password"
  type        = string
  sensitive   = true
}

variable "windows_sku" {
  description = "Windows Server image SKU"
  type        = string
  default     = "2022-datacenter-azure-edition"
}

variable "linux_sku" {
  description = "Linux Server image SKU"
  type        = string
  default     = "ubuntu-24_04-lts"
}

variable "allowed_ssh_source" {
  description = "Source IP or CIDR allowed to SSH. Use '*' for lab, restrict to your IP in production."
  type        = string
  default     = "*"
}


variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    environment = "alz-proj"
    managed_by  = "terraform"
  }
}
