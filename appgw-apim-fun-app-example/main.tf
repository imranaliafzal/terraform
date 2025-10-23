locals {
  tags = {
    project = "apim-appgw-func-private"
    owner   = "Imran Labs"
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location
  tags     = local.tags
}

# ===================== Networking: MAIN VNet (APIM + Functions) =====================
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-shared"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = [var.vnet_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "snet_apim" {
  name                 = "snet-apim"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.snet_apim_cidr]
}

# ===================== Networking: EXT VNet for Application Gateway =================
resource "azurerm_virtual_network" "vnet_ext" {
  name                = var.ext_vnet_name # ends with -ext
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = [var.ext_vnet_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "snet_appgw_ext" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_ext.name
  address_prefixes     = [var.snet_appgw_ext_cidr]
}

# ===================== VNet Peering (Main <-> Ext) =================================
resource "azurerm_virtual_network_peering" "peer_main_to_ext" {
  name                      = "peer-main-to-ext"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.vnet.name
  remote_virtual_network_id = azurerm_virtual_network.vnet_ext.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "peer_ext_to_main" {
  name                      = "peer-ext-to-main"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.vnet_ext.name
  remote_virtual_network_id = azurerm_virtual_network.vnet.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# ===================== Private DNS for APIM Internal FQDN ==========================
# Zone = the domain part after the first label of apim_internal_fqdn.
# Example: api.contoso.internal -> zone "contoso.internal", record "api"
resource "azurerm_private_dns_zone" "internal" {
  name                = join(".", slice(split(".", var.apim_internal_fqdn), 1, length(split(".", var.apim_internal_fqdn))))
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

# ===================== NSG for APIM subnet =====================
resource "azurerm_network_security_group" "nsg_apim" {
  name                = "nsg-apim-internal"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  security_rule {
    name                       = "in-allow-vnet-https"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow HTTPS from VNet clients to APIM gateway (internal mode)"
  }

  security_rule {
    name                       = "in-allow-apim-mgmt-3443"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["3443"]
    source_address_prefix      = "ApiManagement"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow APIM management endpoint (Azure control plane) on 3443"
  }

  security_rule {
    name                       = "in-allow-azlb-6390"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["6390"]
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow Azure internal load balancer probe"
  }

#   Optional: enable if recommended for your SKU/scale
   security_rule {
     name                       = "in-allow-azlb-6391"
     priority                   = 121
     direction                  = "Inbound"
     access                     = "Allow"
     protocol                   = "Tcp"
     source_port_range          = "*"
     destination_port_ranges    = ["6391"]
     source_address_prefix      = "AzureLoadBalancer"
     destination_address_prefix = "VirtualNetwork"
     description                = "Optional additional health monitoring"
   }

  # ------- Outbound rules (minimum set per MS docs) -------
  security_rule {
    name                       = "out-allow-internet-80"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Internet"
    description                = "Allow CRL/OCSP/cert validation over HTTP"
  }

  security_rule {
    name                       = "out-allow-storage-443"
    priority                   = 210
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Storage"
    description                = "Allow Azure Storage dependency"
  }

  security_rule {
    name                       = "out-allow-azuremonitor"
    priority                   = 220
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["1886","443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureMonitor"
    description                = "Allow diagnostics/metrics to Azure Monitor"
  }

  security_rule {
    name                       = "out-allow-entra-443"
    priority                   = 230
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureActiveDirectory"
    description                = "Allow Entra ID (login.microsoftonline.com etc.)"
  }

  # Allow infra ports for backend health (v2: 65200-65535)
  security_rule {
    name                       = "Allow-GatewayManager-Infra-Ports"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["65200-65535"]
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  # Keep AzureLoadBalancer allow
  security_rule {
    name                       = "Allow-AzureLB"
    priority                   = 310
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Your listener ports (example: 443)
  security_rule {
    name                       = "Allow-Client-443"
    priority                   = 320
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Outbound must allow Internet
  security_rule {
    name                       = "Allow-Internet-Out"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
  # Optional if you use these:
  # security_rule { ... destination_address_prefix = "Sql";      destination_port_ranges = ["1433"] }
  # security_rule { ... destination_address_prefix = "EventHub"; destination_port_ranges = ["5671","5672","443"] }
}

# Associate NSG with the APIM subnet
resource "azurerm_subnet_network_security_group_association" "apim_subnet_assoc" {
  subnet_id                 = azurerm_subnet.snet_apim.id
  network_security_group_id = azurerm_network_security_group.nsg_apim.id
}

# ===================== APIM Mock API =====================
resource "azurerm_api_management_api" "mock_api" {
  name                = "mock-api"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name

  display_name = "Mock API"
  path         = "mock"
  protocols    = ["https"]

  # No service_url -> backend-less API (fine for mock/return-response)
  revision = "1"
#  tags     = local.tags
}

resource "azurerm_api_management_api_operation" "mock_get_hello" {
  operation_id        = "get-hello"
  api_name            = azurerm_api_management_api.mock_api.name
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name

  display_name = "Get Hello"
  method       = "GET"
  url_template = "/hello"
  description  = "Returns a mock JSON response"
}
resource "azurerm_api_management_api_operation_policy" "mock_get_hello_policy" {
  api_name            = azurerm_api_management_api.mock_api.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  operation_id        = azurerm_api_management_api_operation.mock_get_hello.operation_id

  xml_content = <<POLICY
<policies>
  <inbound>
    <base />
    <set-header name="Content-Type" exists-action="override">
      <value>application/json</value>
    </set-header>
    <return-response response-variable-name="mockResponse">
      <set-status code="200" reason="OK" />
      <set-header name="Cache-Control" exists-action="override">
        <value>no-store</value>
      </set-header>
      <set-body>
        {
          "message": "hello from APIM mock",
          "path": "/mock/hello"
        }
      </set-body>
    </return-response>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
POLICY
}

# ===================== APIM (Internal Mode) =======================================
resource "azurerm_api_management" "apim" {
  name                = "apim-internal-demo-imr-labs"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  publisher_name  = "Imran Labs"
  publisher_email = "imran.ali.afzal@gmail.com"

  sku_name = "${var.apim_sku}_1"

  virtual_network_configuration {
    subnet_id = azurerm_subnet.snet_apim.id
  }
  virtual_network_type = "Internal"

  tags = local.tags

  depends_on = [
        azurerm_subnet_network_security_group_association.apim_subnet_assoc
    ]
}

# Bind the APIM gateway (proxy) to your internal FQDN using a local PFX
resource "azurerm_api_management_custom_domain" "apim_domain" {
  api_management_id = azurerm_api_management.apim.id

  # 3.x provider: use 'gateway' instead of 'proxy'
  gateway {
    host_name            = var.apim_internal_fqdn              # e.g., api.imranlabs.internal
    certificate          = filebase64(var.apim_pfx_path)       # base64 of your PFX
    certificate_password = var.apim_pfx_password
    negotiate_client_certificate = false
    # default_ssl_binding = true   # optional; set if you want this to be default binding
  }

  # If you later add developer_portal/portal/management/scm, they’re sibling blocks.
}


# A record: <first label> -> APIM private IP (e.g., "api" -> 10.10.2.x)
resource "azurerm_private_dns_a_record" "apim_a" {
  name                = element(split(".", var.apim_internal_fqdn), 0)
  zone_name           = azurerm_private_dns_zone.internal.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = 300
  records             = [azurerm_api_management.apim.private_ip_addresses[0]]
}

# ===================== Application Gateway (v2) ===================================
resource "azurerm_public_ip" "pip_appgw" {
  name                = "pip-appgw"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_application_gateway" "agw" {
  name                = "agw-public-to-apim"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  sku {
    name     = var.appgw_sku      # WAF_v2 or Standard_v2
    tier     = var.appgw_sku
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = azurerm_subnet.snet_appgw_ext.id
  }

  frontend_port {
    name = "fp-https"
    port = 443
  }

  frontend_ip_configuration {
    name                 = "fip-public"
    public_ip_address_id = azurerm_public_ip.pip_appgw.id
  }

  # Inline PFX (no Key Vault)
  ssl_certificate {
    name     = "appgw-public-cert"
    data     = filebase64(var.appgw_pfx_path)
    password = var.appgw_pfx_password
  }

  backend_address_pool {
    name  = "pool-apim"
    fqdns = [var.apim_internal_fqdn] # resolves via private DNS to APIM private IP
  }

  probe {
    name                                      = "probe-apim-https"
    protocol                                  = "Https"
    # host = var.apim_internal_fqdn         # keep this REMOVED since we pick from backend
    path                                      = "/mock/hello"   # <-- UPDATED to hit the mock endpoint
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
    match {
      status_code = ["200-399"]
    }
  }


  backend_http_settings {
    name                                = "bhs-apim-https"
    port                                = 443
    protocol                            = "Https"
    cookie_based_affinity               = "Disabled"
    request_timeout                     = 60
    probe_name                          = "probe-apim-https"
    pick_host_name_from_backend_address = true
  }

  http_listener {
    name                           = "listener-https"
    frontend_ip_configuration_name = "fip-public"
    frontend_port_name             = "fp-https"
    protocol                       = "Https"
    ssl_certificate_name           = "appgw-public-cert"
    host_name                      = var.appgw_public_fqdn
  }

  request_routing_rule {
    name                       = "rule-to-apim"
    rule_type                  = "Basic"
    http_listener_name         = "listener-https"
    backend_address_pool_name  = "pool-apim"
    backend_http_settings_name = "bhs-apim-https"
    priority                   = 100
  }
}
