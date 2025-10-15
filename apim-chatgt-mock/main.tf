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
        <!-- Decide: do we need to look at cookie? -->
        <choose>
            <when condition="@{
          var auth = context.Request.Headers.GetValueOrDefault("Authorization", "") ?? "";
          if (auth.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)) {
              var t = auth.Substring(7).Trim();
              return string.IsNullOrEmpty(t); // if header is empty return true --> use cookie. return false if the header has token
          }
          return true; // Authorization header not found use cookie
      }">
                <!-- We are inside the WHEN body (only runs if we need cookie) -->
                <!-- Parse rt_session cookie (raw token) -->
                <set-variable name="rt_session_token" value="@{
            var cookieHeader = context.Request.Headers.GetValueOrDefault("Cookie", "") ?? "";
            if (string.IsNullOrEmpty(cookieHeader)) {return "";}
            string token = "";
            var parts = cookieHeader.Split(new[]{';'}, System.StringSplitOptions.RemoveEmptyEntries);
            for (int i = 0; i < parts.Length; i++) {
                var kv = parts[i].Split(new[]{'='}, 2);
                var k = kv[0].Trim();
                var v = kv.Length > 1 ? kv[1] : "";
                if (string.Equals(k, "rt_session", System.StringComparison.OrdinalIgnoreCase)) {
                    token = System.Net.WebUtility.UrlDecode(v ?? "").Trim();
                    break;
                }
            }
            return token;
        }" />
                <!-- If rt_session_token has value then use it and set Authorization header with it -->
                <choose>
                    <when condition="@(!string.IsNullOrEmpty((string)context.Variables["rt_session_token"]))">
                        <set-header name="Authorization" exists-action="override">
                            <value>@("Bearer " + (string)context.Variables["rt_session_token"])</value>
                        </set-header>
                    </when>
                </choose>
            </when>
        </choose>
        <!-- Process the Authorization Header -->
        <!-- Pull raw bearer string (no validation yet) -->
        <set-variable name="rawJwt" value="@{
      var auth = context.Request.Headers.GetValueOrDefault("Authorization", "");
      return auth?.StartsWith("Bearer ") == true ? auth.Substring(7) : auth;
  }" />
        <!-- if rawJwt is empty return with error -->
        <choose>
            <when condition="@(string.IsNullOrEmpty((string)context.Variables["rawJwt"]))">
                <return-response>
                    <set-status code="460" reason="Unauthorized"/>
                    <set-header name="Content-Type" exists-action="override">
                        <value>application/json</value>
                    </set-header>
                    <set-body>@{
                                    var json = new Newtonsoft.Json.Linq.JObject(
                                    new Newtonsoft.Json.Linq.JProperty("statusCode", "460"),
                                    new Newtonsoft.Json.Linq.JProperty("message", "Unauthorized"),
                                    new Newtonsoft.Json.Linq.JProperty("description", "Unauthorized")
                                );
                                    return json.ToString();
                            }</set-body>
                </return-response>
            </when>
        </choose>
        <set-variable name="jwtPayloadJson" value="@{
    var t = (string)context.Variables["rawJwt"];
    if (string.IsNullOrEmpty(t)) { return ""; }

    var parts = t.Split('.');
    if (parts.Length < 2) { return ""; }

    // base64url -> base64
    var b64 = parts[1].Replace("-", "+").Replace("_", "/");
    var mod = b64.Length % 4;
    if (mod == 2) {b64 += "==";}
    else if (mod == 3) {b64 += "=";}
    else if (mod == 1) { return ""; } // invalid length; bail out

    var bytes = System.Convert.FromBase64String(b64);
    var json = System.Text.Encoding.UTF8.GetString(bytes);
    return json;
}" />
        <set-variable name="firmName" value="@{
            var s = (string)context.Variables["jwtPayloadJson"];
            if (string.IsNullOrEmpty(s)) {return "";}
            return ((string)Newtonsoft.Json.Linq.JObject.Parse(s).SelectToken("iss"));
        }" />
        <set-variable name="aud" value="@{
            var s = (string)context.Variables["jwtPayloadJson"];
            if (string.IsNullOrEmpty(s)) {return "";}
            return (string)Newtonsoft.Json.Linq.JObject.Parse(s).SelectToken("aud");
        }" />
        <set-variable name="oidc_config_url" value="@("https://login.firefly.com/idp/"+ (string)context.Variables["firmName"]+ "/.well-known/openid-configuration")" />
        <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized" require-scheme="Bearer" output-token-variable-name="jwtToken">
            <openid-config url="@((string)context.Variables["oidc_config_url"])" />
            <audiences>
                <audience>@((string)context.Variables["aud"])</audience>
            </audiences>
        </validate-jwt>
        <!-- Place subsequent policies that need parsed claims here -->
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
        <!-- Capture error reason, error message and error source  -->
        <set-variable name="jwt_error_source" value="@(context.LastError?.Source ?? string.Empty)" />
        <set-variable name="jwt_error_reason" value="@(context.LastError?.Reason ?? string.Empty)" />
        <set-variable name="jwt_error_message" value="@(context.LastError?.Message ?? string.Empty)" />
        <set-variable name="is_jwt" value="@(string.Equals((string)context.Variables["jwt_error_source"], "validate-jwt", StringComparison.OrdinalIgnoreCase))" />
        <choose>
            <when condition="@((bool)context.Variables["is_jwt"])">
                <choose>
                    <when condition="@(string.Equals((string)context.Variables["jwt_error_reason"],"TokenNotPresent",StringComparison.OrdinalIgnoreCase))">
                        <set-status code="460" reason="Unauthorized" />
                    </when>
                    <when condition="@(string.Equals((string)context.Variables["jwt_error_reason"], "TokenInvalidSignature", StringComparison.OrdinalIgnoreCase))">
                        <set-status code="461" reason="Unauthorized" />
                    </when>
                    <when condition="@(string.Equals((string)context.Variables["jwt_error_reason"],"TokenAudienceNotAllowed",StringComparison.OrdinalIgnoreCase))">
                        <set-status code="462" reason="Unauthorized" />
                    </when>
                    <when condition="@(string.Equals((string)context.Variables["jwt_error_reason"],"TokenIssuerNotAllowed",StringComparison.OrdinalIgnoreCase))">
                        <set-status code="463" reason="Unauthorized" />
                    </when>
                    <when condition="@(string.Equals((string)context.Variables["jwt_error_reason"], "TokenExpired", StringComparison.OrdinalIgnoreCase) )">
                        <set-status code="464" reason="Unauthorized" />
                    </when>
                    <when condition="@(string.Equals((string)context.Variables["jwt_error_reason"], "TokenSignatureKeyNotFound", StringComparison.OrdinalIgnoreCase))">
                        <set-status code="465" reason="Unauthorized" />
                    </when>
                    <when condition="@(string.Equals((string)context.Variables["jwt_error_reason"], "TokenClaimNotFound", StringComparison.OrdinalIgnoreCase))">
                        <set-status code="466" reason="Unauthorized" />
                    </when>
                    <when condition="@(string.Equals((string)context.Variables["jwt_error_reason"], "TokenClaimValueNotAllowed", StringComparison.OrdinalIgnoreCase))">
                        <set-status code="467" reason="Unauthorized" />
                    </when>
                    <when condition="@(string.Equals((string)context.Variables["jwt_error_reason"], "Invalid JWT.", StringComparison.OrdinalIgnoreCase))">
                        <set-status code="468" reason="Unauthorized" />
                    </when>
                    <otherwise />
                </choose>
                <!--set-header name="Content-Type" exists-action="override">
                    <value>application/json</value>
                </set-header-->
                <!--set-body>@{
                                    // Use the response’s current status code
                                    var code = (int)(context.Response?.StatusCode ?? 0);
                                    var json = new Newtonsoft.Json.Linq.JObject(
                                                        new Newtonsoft.Json.Linq.JProperty("statusCode", code),
                                                        new Newtonsoft.Json.Linq.JProperty("message", (string)context.Variables["jwt_error_reason"]),
                                                        new Newtonsoft.Json.Linq.JProperty("description", (string)context.Variables["jwt_error_message"])
                                                    );
                                    return json.ToString();
                            }</set-body-->
            </when>
            <otherwise />
        </choose>
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
