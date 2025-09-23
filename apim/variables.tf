# variables.tf
variable "location"         { default = "eastus2" }
variable "rg_name"          { default = "rg-gw-apim-imr" }
variable "vnet_name"        { default = "vnet_eus2_npe" }
variable "appgw_subnet_cidr"{ default = "10.10.1.0/24" }  # /24 recommended for AppGW v2
variable "apim_subnet_cidr" { default = "10.10.2.0/26" }  # /26 or larger for APIM
variable "appgw_subnet_name"{ default = "snet_appgw" }
variable "apim_subnet_name" { default = "snet_apim" }
variable "appgw_name"       { default = "agw-eus2-npe" }
variable "apim_name"        { default = "apim-internal-eus2" } # must be unique globally
variable "apim_sku"         { default = "Developer_1" }   # or "Premium_1"
variable "enable_public_access" {default = false}
# TLS certificate for AppGW (stored in Key Vault). Use key_vault_secret_id here:
#variable "appgw_cert_secret_id" { description = "Key Vault secret ID for PFX" }
