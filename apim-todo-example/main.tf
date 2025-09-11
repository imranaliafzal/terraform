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

  revision            = "1"
  display_name        = "Todos API (mock)"
  path                = "todos"
  protocols           = ["https"]

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