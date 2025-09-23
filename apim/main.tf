terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      # 3.90+ includes many APIM VNet fixes
      version = ">= 3.90.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# -------------------------
# Variables (safe defaults)
# -------------------------
variable "location"               { default = "eastus2" }
variable "resource_group_name"    { default = "rg-apim-internal-demo" }
variable "vnet_name"              { default = "vnet-apim-demo" }
variable "address_space"          { default = ["10.50.0.0/16"] }
variable "apim_subnet_name"       { default = "snet-apim" }
variable "apim_subnet_prefix"     { default = "10.50.1.0/24" }

variable "apim_name"              { default = "apim-internal-demo-eus2" }
variable "publisher_name"         { default = "Imran" }
variable "publisher_email"        { default = "imran@example.com" }
# Set to true if you explicitly want to allow port 80 on the gateway
variable "allow_http_80"          { default = false }

# ------------------------------------------------
# 1) Resource Group, VNet, Subnet (no delegation)
# ------------------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  address_space       = var.address_space
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "apim" {
  name                 = var.apim_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.apim_subnet_prefix]

  # Recommended service endpoints for APIM dependencies
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.Sql",
    "Microsoft.EventHub",
    "Microsoft.KeyVault"
  ]
}

# -----------------------------------------
# 2) NSG with Microsoft-recommended rules
# -----------------------------------------
resource "azurerm_network_security_group" "apim_nsg" {
  name                = "nsg-${var.apim_subnet_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Inbound: APIM control-plane (management) from ApiManagement service tag (TCP 3443)
  security_rule {
    name                       = "in-apim-mgmt-3443"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3443"
    source_address_prefix      = "ApiManagement"
    destination_address_prefix = "VirtualNetwork"
  }

  # Inbound: Azure infrastructure load balancer probe (TCP 6390)
  security_rule {
    name                       = "in-azure-lb-6390"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6390"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "VirtualNetwork"
  }

  # Inbound: Internal clients in VNet to APIM over HTTPS (and optionally HTTP)
  security_rule {
    name                       = "in-vnet-https-443"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  dynamic "security_rule" {
    for_each = var.allow_http_80 ? [1] : []
    content {
      name                       = "in-vnet-http-80"
      priority                   = 121
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    }
  }

  # Outbound: certificate chain/CRL/OCSP
  security_rule {
    name                       = "out-internet-80"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Internet"
  }

  # Outbound: dependencies
  security_rule {
    name                       = "out-storage-443"
    priority                   = 210
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Storage"
  }

  security_rule {
    name                       = "out-sql-1433"
    priority                   = 220
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Sql"
  }

  security_rule {
    name                       = "out-keyvault-443"
    priority                   = 230
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureKeyVault"
  }

  security_rule {
    name                        = "out-azuremonitor-1886-443"
    priority                    = 240
    direction                   = "Outbound"
    access                      = "Allow"
    protocol                    = "Tcp"
    source_port_range           = "*"
    destination_port_ranges     = ["1886", "443"]
    source_address_prefix       = "VirtualNetwork"
    destination_address_prefix  = "AzureMonitor"
  }

  # Optional: if you use custom DNS servers, allow DNS to your resolver
  # security_rule {
  #   name                       = "out-dns-53"
  #   priority                   = 250
  #   direction                  = "Outbound"
  #   access                     = "Allow"
  #   protocol                   = "Udp"
  #   source_port_range          = "*"
  #   destination_port_range     = "53"
  #   source_address_prefix      = "VirtualNetwork"
  #   destination_address_prefix = "VirtualNetwork"
  # }
}

# Associate NSG to APIM subnet (this fixes the common 400 about NSG missing)
resource "azurerm_subnet_network_security_group_association" "apim_assoc" {
  subnet_id                 = azurerm_subnet.apim.id
  network_security_group_id = azurerm_network_security_group.apim_nsg.id
}

# -------------------------------------------------------
# 3) APIM in INTERNAL mode, injected into APIM subnet
# -------------------------------------------------------
resource "azurerm_api_management" "apim" {
  name                = var.apim_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  publisher_name  = var.publisher_name
  publisher_email = var.publisher_email

  sku_name = "Developer_1" # or "Premium_1" for prod/zone/multi-region

  # INTERNAL VNet mode
  virtual_network_type = "Internal"
  virtual_network_configuration {
    subnet_id = azurerm_subnet.apim.id
  }

  # IMPORTANT:
  # Do NOT set public_network_access_enabled = false here unless you're *also*
  # creating an inbound Private Endpoint for APIM. Otherwise the create will 400.
  # (APIM still uses a public VIP for control-plane mgmt on 3443.) See docs.
}

# -------------------------------------------------------
# 4) Private DNS zone for internal name resolution
# -------------------------------------------------------
resource "azurerm_private_dns_zone" "apim_zone" {
  name                = "azure-api.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "apim_zone_link" {
  name                  = "pdnslink-${var.vnet_name}"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.apim_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}

locals {
  apim_private_ip = try(azurerm_api_management.apim.private_ip_addresses[0], null)

  # Labels within the azure-api.net zone
  apim_a_records = {
    # "<record_label>" = "<IP>"
    "${var.apim_name}"               = local.apim_private_ip
    "${var.apim_name}.portal"        = local.apim_private_ip
    "${var.apim_name}.developer"     = local.apim_private_ip
    "${var.apim_name}.management"    = local.apim_private_ip
    "${var.apim_name}.scm"           = local.apim_private_ip
  }
}

resource "azurerm_private_dns_a_record" "apim_records" {
  for_each            = { for k, v in local.apim_a_records : k => v if v != null }
  name                = each.key
  zone_name           = azurerm_private_dns_zone.apim_zone.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = 300
  records             = [each.value]

  depends_on = [azurerm_api_management.apim]
}

output "apim_private_ip" {
  value       = local.apim_private_ip
  description = "APIM private VIP (use this for private DNS records)"
}
