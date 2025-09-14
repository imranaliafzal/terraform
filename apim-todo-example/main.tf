resource "azurerm_resource_group" "rg" {
  name     = var.resource_group
  location = var.location
}

# APIM instance (Developer tier is cheapest for end-to-end testing)
resource "azurerm_api_management" "apim" {
  name                = var.apim_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = "Developer_1"
}

# A blank HTTP API
resource "azurerm_api_management_api" "todos_api" {
  name                = "todos"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name

  revision     = "1"
  display_name = "Todos API (mock)"
  path         = "todos"
  protocols    = ["https"]

  # no import - we’ll manage operations manually
}

# Define one GET /todos operation
resource "azurerm_api_management_api_operation" "get_todos" {
  operation_id        = "get-todos"
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  api_name            = azurerm_api_management_api.todos_api.name

  display_name = "Get Todos"
  method       = "GET"
  url_template = "/"

  response {
    status_code = 200
    description = "OK"
    representation {
      content_type = "application/json"
      # a schema is optional for mocking; we’ll just return a static body via policy
    }
  }
}

# Operation-level policy that returns a static JSON mock
# (You can also put this at the API level with azurerm_api_management_api_policy if you prefer)
resource "azurerm_api_management_api_operation_policy" "get_todos_policy" {
  api_name            = azurerm_api_management_api.todos_api.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  operation_id        = azurerm_api_management_api_operation.get_todos.operation_id

  xml_content = <<POLICY
<policies>
  <inbound>
    <base />
    <cors allow-credentials="true">
      <allowed-origins>
        <origin>http://localhost:5173</origin>
      </allowed-origins>
      <allowed-methods>
        <method>GET</method><method>POST</method><method>PUT</method><method>DELETE</method><method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>authorization</header><header>content-type</header>
      </allowed-headers>
      <expose-headers>
        <header>content-length</header>
      </expose-headers>
    </cors>
    <validate-azure-ad-token tenant-id="e3ad7e9e-4e1e-419a-8da6-398e5bc8da69"
                             failed-validation-httpcode="401"
                             failed-validation-error-message="Unauthorized."
                             output-token-variable-name="jwt">
      <audiences>
        <audience>449438c6-50f7-4ff7-b42e-4563c537eaab</audience>
      </audiences>
      <required-claims>
        <claim name="scp" match="any">
          <value>todos.read</value>
        </claim>
      </required-claims>
    </validate-azure-ad-token>
    <!-- Optional: forward user OID and name -->
    <set-header name="x-user-oid" exists-action="override">
      <value>@(((Jwt)context.Variables["jwt"]).Claims["oid"].FirstOrDefault())</value>
    </set-header>
    <set-header name="x-user-name" exists-action="override">
      <value>@(((Jwt)context.Variables["jwt"]).Claims["name"].FirstOrDefault())</value>
    </set-header>
    <!-- choose one of the two approaches below -->
    <!-- A) Use mock-response (prefers examples/schemas if present) -->
    <!-- <mock-response status-code="200" content-type="application/json" /> -->

    <!-- B) Return a fixed body explicitly -->
    <return-response>
      <set-status code="200" reason="OK" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>
        [
          {"id":"1","userId":"00000000-0000-0000-0000-000000000000","title":"Buy milk","done":false},
          {"id":"2","userId":"00000000-0000-0000-0000-000000000000","title":"Pay bill","done":true}
        ]
      </set-body>
    </return-response>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
POLICY
}

output "gateway_url_example" {
  value = "${azurerm_api_management.apim.gateway_regional_url}/${azurerm_api_management_api.todos_api.path}"
}