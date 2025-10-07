variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID."
}

variable "location" {
  type        = string
  default     = "East US"
  description = "Azure region."
}

variable "name_prefix" {
  type        = string
  default     = "demo-chatgpt"
  description = "Prefix for resource names (letters, numbers, hyphens)."
}

variable "publisher_name" {
  type        = string
  default     = "Example Publisher"
  description = "APIM publisher name."
}

variable "publisher_email" {
  type        = string
  default     = "admin@example.com"
  description = "APIM publisher email."
}

variable "tags" {
  type        = map(string)
  default     = { project = "apim-chatgpt-mock", env = "dev" }
  description = "Tags applied to resources."
}
