# ============================================================
# main.tf
# ============================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.3.0"

  # Terraform Cloud backend — workspace settings managed in TFC UI
  cloud {
    organization = "yarnamcorp"
    workspaces {
      name = "TerraformCI"
    }
  }
}

# ============================================================
# Provider — credentials injected via Terraform Cloud
# Set these as sensitive Environment Variables in TFC workspace:
#   ARM_CLIENT_ID       → Service Principal App ID
#   ARM_CLIENT_SECRET   → Service Principal Secret
#   ARM_TENANT_ID       → Azure AD Tenant ID
#   ARM_SUBSCRIPTION_ID → Target Subscription ID
# ============================================================

provider "azurerm" {
  features {}
}

# ============================================================
# Resource Group
# ============================================================

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ============================================================
# Virtual Network & Subnet
# ============================================================

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.vm_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "subnet" {
  name                 = "snet-${var.vm_name}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ============================================================
# Network Security Group (Allow RDP 3389, Deny-All fallback)
# ============================================================

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${var.vm_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-RDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.allowed_rdp_source
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ============================================================
# Public IP Address
# ============================================================

resource "azurerm_public_ip" "pip" {
  name                = "pip-${var.vm_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# ============================================================
# Network Interface Card (NIC)
# ============================================================

resource "azurerm_network_interface" "nic" {
  name                = "nic-${var.vm_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig-${var.vm_name}"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ============================================================
# Windows Server Virtual Machine
# ============================================================

resource "azurerm_windows_virtual_machine" "vm" {
  name                = var.vm_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  tags                = var.tags

  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  os_disk {
    name                 = "osdisk-${var.vm_name}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = var.windows_sku
    version   = "latest"
  }

  enable_automatic_updates = true
  patch_mode               = "AutomaticByOS"

  boot_diagnostics {}
}
