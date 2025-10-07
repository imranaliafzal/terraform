terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.8"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# -----------------------------------------
# Resource Group
# -----------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = var.tags
}

# -----------------------------------------
# APIM (Public/External gateway for simplicity)
# -----------------------------------------
resource "azurerm_api_management" "apim" {
  name                = "${var.name_prefix}-apim"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  publisher_name  = var.publisher_name
  publisher_email = var.publisher_email

  sku_name = "Developer_1" # cheapest for dev/test

  # Leave as default (public) so you can curl it easily.
  # If you later need VNET/Internal, we can extend this.
  tags = var.tags
}

# -----------------------------------------
# “chatgpt” API (no subscription key required for quick testing)
# -----------------------------------------
resource "azurerm_api_management_api" "chatgpt_api" {
  name                = "chatgpt"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name

  revision              = "1"
  display_name          = "ChatGPT Mock API"
  path                  = "chatgpt"
  protocols             = ["https"]
  subscription_required = false

  # Optional backend URL (not used since we mock the response)
  service_url = null
}

# Optional: permissive CORS on this API (handy while testing)
resource "azurerm_api_management_api_policy" "chatgpt_api_policy" {
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  api_name            = azurerm_api_management_api.chatgpt_api.name

  # ensure API is fully created before policy attempt
  depends_on = [azurerm_api_management_api.chatgpt_api]

  xml_content = <<POLICY
<policies>
  <inbound>
    <base />
    <!-- Pull raw bearer string (no validation yet) -->
  <set-variable name="rawJwt" value='@{
      var auth = context.Request.Headers.GetValueOrDefault("Authorization", "");
      return auth?.StartsWith("Bearer ") == true ? auth.Substring(7) : auth;
  }' />


    <validate-jwt header-name="Authorization"
                  require-scheme="Bearer"
                  failed-validation-httpcode="401"
                  failed-validation-error-message="Unauthorized" output-token-variable-name="jwtToken">
      <openid-config url="https://login-uat.fisglobal.com/idp/revenueinsight/.well-known/openid-configuration" />
      <audiences>
        <audience>revenueinsightfis</audience>
      </audiences>
    </validate-jwt>
    <!-- Place subsequent policies that need parsed claims here -->
        <set-header name="user-id" exists-action="override">
            <value>@(context.Variables.GetValueOrDefault<Jwt>("jwtToken")?.Claims?.GetValueOrDefault("sub"))</value>
        </set-header>
        <set-header name="user-roles" exists-action="override">
            <value>@(context.Variables.GetValueOrDefault<Jwt>("jwtToken")?.Claims?.GetValueOrDefault("roles"))</value>
        </set-header>
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



# -----------------------------------------
# Operation: POST /v1/chat/completions  (mocked)
# URL will be: https://{gateway}/chatgpt/v1/chat/completions
# -----------------------------------------
resource "azurerm_api_management_api_operation" "chat_completion" {
  operation_id        = "post-chat-completions"
  api_name            = azurerm_api_management_api.chatgpt_api.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name

  display_name = "Create chat completion (mock)"
  method       = "POST"
  url_template = "/v1/chat/completions"
  description  = "Returns a mocked ChatGPT-like response."

  request {
    description = "Chat completion request body."
    representation {
      content_type = "application/json"
      # Schema omitted for brevity; not required for mock.
    }
  }

  response {
    status_code = 200
    representation {
      content_type = "application/json"
    }
  }
}

# Attach a policy on the operation to return a static JSON
resource "azurerm_api_management_api_operation_policy" "chat_completion_policy" {
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  api_name            = azurerm_api_management_api.chatgpt_api.name
  operation_id        = azurerm_api_management_api_operation.chat_completion.operation_id

  xml_content = <<POLICY
<policies>
  <inbound>
    <base />
    <return-response>
      <set-status code="200" reason="OK" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>{
        "id": "chatcmpl-mock-12345",
        "object": "chat.completion",
        "created": 1700000000,
        "model": "gpt-4.1-mini",
        "choices": [
          {
            "index": 0,
            "message": {
              "role": "assistant",
              "content": "Hello! This is a mocked response coming from Azure APIM."
            },
            "finish_reason": "stop"
          }
        ],
        "usage": {
          "prompt_tokens": 12,
          "completion_tokens": 10,
          "total_tokens": 22
        }
      }</set-body>
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

# -----------------------------------------
# Useful outputs
# -----------------------------------------
output "apim_gateway_url" {
  value       = "https://${azurerm_api_management.apim.gateway_url}"
  description = "APIM public gateway base URL."
}

output "mock_chat_completions_url" {
  value       = "https://${azurerm_api_management.apim.gateway_url}/${azurerm_api_management_api.chatgpt_api.path}/v1/chat/completions"
  description = "Full URL to the mocked chat completions endpoint."
}
