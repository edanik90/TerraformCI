# ============================================================
# outputs.tf
# ============================================================

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.rg.name
}

output "vm_name" {
  description = "Name of the Windows Server VM"
  value       = azurerm_windows_virtual_machine.vm.name
}

output "public_ip_address" {
  description = "Public IP address to RDP into the VM"
  value       = azurerm_public_ip.pip.ip_address
}

output "private_ip_address" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.nic.private_ip_address
}

output "rdp_connection_string" {
  description = "RDP connection string — paste directly into PowerShell"
  value       = "mstsc /v:${azurerm_public_ip.pip.ip_address}"
}
