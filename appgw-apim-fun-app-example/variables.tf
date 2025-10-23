variable "location"            {
  type = string
  default = "eastus2"
}
variable "rg_name"             {
  type = string
  default = "rg-hubspoke-demo"
}

# Main VNet (APIM + Functions)
variable "vnet_cidr"           {
  type = string
  default = "10.10.0.0/16"
}
variable "snet_apim_cidr"      {
  type = string
  default = "10.10.2.0/24"
}
variable "snet_func_cidr"      {
  type = string
  default = "10.10.3.0/24"
}

# Ext VNet for App Gateway only (must end with -ext)
variable "ext_vnet_name"       {
  type = string
  default = "vnet-shared-ext"
}
variable "ext_vnet_cidr"       {
  type = string
  default = "10.20.0.0/16"
}
variable "snet_appgw_ext_cidr" {
  type = string
  default = "10.20.1.0/24"
}

# Hostnames
variable "apim_internal_fqdn"  {
  type = string
  default = "api.imranlabs.internal"
} # private DNS name for APIM
variable "appgw_public_fqdn"   {
  type = string
  default = "imranaliafzal.duckdns.org"
}      # public DNS you will point to AppGW public IP

# SKUs
variable "apim_sku"            {
  type = string
  default = "Developer"
} # Dev for labs; adjust for prod
variable "appgw_sku"           {
  type = string
  default = "Standard_v2"
}    # or Standard_v2
variable "functions_sku"       {
  type = string
  default = "Y1"
}        # Linux Consumption; for Premium use EP1

# Local PFX certs (no Key Vault)
variable "appgw_pfx_path"      {
  type = string
  default = "./certs/appgw-public.pfx"
}
variable "apim_pfx_path"       {
  type = string
  default = "./certs/apim-internal.pfx"
}
variable "appgw_pfx_password"  {
  type = string
  sensitive = true
}
variable "apim_pfx_password"   {
  type = string
  sensitive = true
}
