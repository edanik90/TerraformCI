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
# Resource Groups
# ============================================================
resource "azurerm_resource_group" "prod_rg" {
  name     = "rg-prod"
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "dmz_rg" {
  name     = "rg-dmz"
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "hub_rg" {
  name     = "rg-hub"
  location = var.location
  tags     = var.tags
}

# ============================================================
# Virtual Networks & Subnets
# ============================================================
resource "azurerm_virtual_network" "vnet_prod" {
  name                = "vnet-prod"
  location            = azurerm_resource_group.prod_rg.location
  resource_group_name = azurerm_resource_group.prod_rg.name
  address_space       = ["10.1.2.0/24"]
  tags                = var.tags
}

resource "azurerm_virtual_network" "vnet_dmz" {
  name                = "vnet-dmz"
  location            = azurerm_resource_group.dmz_rg.location
  resource_group_name = azurerm_resource_group.dmz_rg.name
  address_space       = ["10.1.1.0/24"]
  tags                = var.tags
}

resource "azurerm_virtual_network" "vnet_hub" {
  name                = "vnet-hub"
  location            = azurerm_resource_group.hub_rg.location
  resource_group_name = azurerm_resource_group.hub_rg.name
  address_space       = ["172.16.0.0/24"]
  tags                = var.tags
}

resource "azurerm_subnet" "vnet_prod_subnet" {
  name                 = "subnet"
  resource_group_name  = azurerm_resource_group.prod_rg.name
  virtual_network_name = azurerm_virtual_network.vnet_prod.name
  address_prefixes     = ["10.1.2.0/27"]
}

resource "azurerm_subnet" "vnet_dmz_subnet" {
  name                 = "subnet"
  resource_group_name  = azurerm_resource_group.dmz_rg.name
  virtual_network_name = azurerm_virtual_network.vnet_dmz.name
  address_prefixes     = ["10.1.1.0/27"]
}

resource "azurerm_subnet" "vnet_hub_gateway_subnet" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.hub_rg.name
  virtual_network_name = azurerm_virtual_network.vnet_hub.name
  address_prefixes     = ["172.16.0.0/27"]
}

resource "azurerm_subnet" "vnet_hub_bastion_subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.hub_rg.name
  virtual_network_name = azurerm_virtual_network.vnet_hub.name
  address_prefixes     = ["172.16.0.32/27"]
}

# ============================================================
# Network peerings
# ============================================================
resource "azurerm_virtual_network_peering" "peer_prod_to_hub" {
  name                         = "peer-prod-to-hub"
  resource_group_name          = azurerm_resource_group.prod_rg.name
  virtual_network_name         = azurerm_virtual_network.vnet_prod.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet_hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = true
}

resource "azurerm_virtual_network_peering" "peer_hub_to_prod" {
  name                         = "peer-hub-to-prod"
  resource_group_name          = azurerm_resource_group.hub_rg.name
  virtual_network_name         = azurerm_virtual_network.vnet_hub.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet_prod.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
}

resource "azurerm_virtual_network_peering" "peer_dmz_to_hub" {
  name                         = "peer-dmz-to-hub"
  resource_group_name          = azurerm_resource_group.dmz_rg.name
  virtual_network_name         = azurerm_virtual_network.vnet_dmz.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet_hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = true
}

resource "azurerm_virtual_network_peering" "peer_hub_to_dmz" {
  name                         = "peer-hub-to-dmz"
  resource_group_name          = azurerm_resource_group.hub_rg.name
  virtual_network_name         = azurerm_virtual_network.vnet_hub.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet_dmz.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
}

# ============================================================
# Network Security Group For Production (Allow SSH from Bastion, Deny RDP from Rest)
# ============================================================
resource "azurerm_network_security_group" "nsg_prod" {
  name                = "nsg-prod"
  location            = azurerm_resource_group.prod_rg.location
  resource_group_name = azurerm_resource_group.prod_rg.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-SSH-from-Bastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = azurerm_subnet.vnet_hub_bastion_subnet.address_prefixes[0]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-SSH-From-DMZ"
    priority                   = 160
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.1.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-SSH-for-Rest"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

resource "azurerm_subnet_network_security_group_association" "nsg_assoc_prod" {
  subnet_id                 = azurerm_subnet.vnet_prod_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg_prod.id
}

# ============================================================
# Network Security Group For DMZ (Allow SSH from Bastion, Deny RDP from Rest) 
# ============================================================
resource "azurerm_network_security_group" "nsg_dmz" {
  name                = "nsg-dmz"
  location            = azurerm_resource_group.dmz_rg.location
  resource_group_name = azurerm_resource_group.dmz_rg.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-SSH-from-Bastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = azurerm_subnet.vnet_hub_bastion_subnet.address_prefixes[0]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-SSH-From-Prod"
    priority                   = 150
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.2.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-SSH-for-Rest"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

resource "azurerm_subnet_network_security_group_association" "nsg_assoc_dmz" {
  subnet_id                 = azurerm_subnet.vnet_dmz_subnet.id
  network_security_group_id = azurerm_network_security_group.nsg_dmz.id
}

# ============================================================
# Public IPs
# ============================================================
resource "azurerm_public_ip" "pip_vpn_gateway" {
  name                = "pip-vpn-gateway"
  location            = azurerm_resource_group.hub_rg.location
  resource_group_name = azurerm_resource_group.hub_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_public_ip" "pip_bastion" {
  name                = "pip-bastion"
  location            = azurerm_resource_group.hub_rg.location
  resource_group_name = azurerm_resource_group.hub_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# ============================================================
# Network Interface Cards (NICs)
# ============================================================
resource "azurerm_network_interface" "nic_webapp01" {
  name                = "nic-webapp01"
  location            = azurerm_resource_group.prod_rg.location
  resource_group_name = azurerm_resource_group.prod_rg.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig-webapp01"
    subnet_id                     = azurerm_subnet.vnet_prod_subnet.id
    private_ip_address_allocation = "Dynamic"
    #public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface" "nic_webserver01" {
  name                = "nic-webserver01"
  location            = azurerm_resource_group.dmz_rg.location
  resource_group_name = azurerm_resource_group.dmz_rg.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig-webserver01"
    subnet_id                     = azurerm_subnet.vnet_dmz_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# ============================================================
# Bastion Host
# ============================================================
resource "azurerm_bastion_host" "bastion" {
  name                = "bastion"
  location            = azurerm_resource_group.hub_rg.location
  resource_group_name = azurerm_resource_group.hub_rg.name
  tags                = var.tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.vnet_hub_bastion_subnet.id
    public_ip_address_id = azurerm_public_ip.pip_bastion.id
  }
}

# ============================================================
# Virtual Network Gateway (VPN Gateway)
# ============================================================
resource "azurerm_virtual_network_gateway" "vpn_gateway" {
  name                = "vpn-gateway"
  location            = azurerm_resource_group.hub_rg.location
  resource_group_name = azurerm_resource_group.hub_rg.name

  type     = "Vpn"
  vpn_type = "RouteBased"
  sku      = "VpnGw1AZ"

  active_active = false

  ip_configuration {
    name                          = "vpn-gateway-config"
    public_ip_address_id          = azurerm_public_ip.pip_vpn_gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.vnet_hub_gateway_subnet.id
  }

  tags = var.tags
}

# ============================================================
# Route Tables for Spoke-to-Spoke Communication via VPN Gateway
# ============================================================

resource "azurerm_route_table" "rt_prod_to_hub" {
  name                = "rt-prod-to-hub"
  location            = azurerm_resource_group.prod_rg.location
  resource_group_name = azurerm_resource_group.prod_rg.name
  tags                = var.tags

  route {
    name           = "to-dmz-via-hub"
    address_prefix = "10.1.1.0/24"
    next_hop_type  = "VirtualNetworkGateway"
  }

  route {
    name           = "to-hub-bastion"
    address_prefix = "172.16.0.0/24"
    next_hop_type  = "VirtualNetworkGateway"
  }
}

resource "azurerm_route_table" "rt_dmz_to_hub" {
  name                = "rt-dmz-to-hub"
  location            = azurerm_resource_group.dmz_rg.location
  resource_group_name = azurerm_resource_group.dmz_rg.name
  tags                = var.tags

  route {
    name           = "to-prod-via-hub"
    address_prefix = "10.1.2.0/24"
    next_hop_type  = "VirtualNetworkGateway"
  }

  route {
    name           = "to-hub-bastion"
    address_prefix = "172.16.0.0/24"
    next_hop_type  = "VirtualNetworkGateway"
  }
}

resource "azurerm_subnet_route_table_association" "prod_subnet_assoc" {
  subnet_id      = azurerm_subnet.vnet_prod_subnet.id
  route_table_id = azurerm_route_table.rt_prod_to_hub.id
}

resource "azurerm_subnet_route_table_association" "dmz_subnet_assoc" {
  subnet_id      = azurerm_subnet.vnet_dmz_subnet.id
  route_table_id = azurerm_route_table.rt_dmz_to_hub.id
}

# ============================================================
# Linux Server Virtual Machines
# ============================================================
resource "azurerm_linux_virtual_machine" "webapp01" {
  name                            = "WEBAPP01"
  resource_group_name             = azurerm_resource_group.prod_rg.name
  location                        = azurerm_resource_group.prod_rg.location
  size                            = var.vm_size
  priority                        = "Spot"
  eviction_policy                 = "Deallocate"
  max_bid_price                   = -1
  disable_password_authentication = false
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.nic_webapp01.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

resource "azurerm_linux_virtual_machine" "webserver01" {
  name                            = "WEBSERVER01"
  resource_group_name             = azurerm_resource_group.dmz_rg.name
  location                        = azurerm_resource_group.dmz_rg.location
  size                            = var.vm_size
  priority                        = "Spot"
  eviction_policy                 = "Deallocate"
  max_bid_price                   = -1
  disable_password_authentication = false
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.nic_webserver01.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}
/* resource "azurerm_windows_virtual_machine" "vm" {
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
} */