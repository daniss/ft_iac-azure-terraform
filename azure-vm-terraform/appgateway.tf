data "azurerm_client_config" "current" {}

# Create application gateway
resource "azurerm_application_gateway" "app_gw" {
  name                = "${random_pet.prefix.id}-app-gw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  zones               = ["1", "2"]
  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }
  gateway_ip_configuration {
    name      = "app-gw-ip-config"
    subnet_id = azurerm_subnet.app_gateway_subnet.id
  }
  frontend_port {
    name = "httpFrontendPort"
    port = 80
  }
  frontend_ip_configuration {
    name                 = "app-gw-frontend-ip"
    public_ip_address_id = azurerm_public_ip.app_gw_public_ip.id
  }
  backend_address_pool {
    name = "app-gw-backend-pool"
  }
  backend_http_settings {
    name                     = "app-gw-backend-http-settings"
    cookie_based_affinity    = "Enabled" # this if for session affinity, which means that requests from the same client go to the same backend instance
    affinity_cookie_name     = "AppGwAffinityCookie"
    port                     = 80
    protocol                 = "Http"
  }
  http_listener {
    name                           = "app-gw-http-listener"
    frontend_ip_configuration_name = "app-gw-frontend-ip"
    frontend_port_name             = "httpFrontendPort"
    protocol                       = "Http"
  }
  request_routing_rule {
    name                       = "app-gw-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "app-gw-http-listener"
    backend_address_pool_name  = "app-gw-backend-pool"
    backend_http_settings_name = "app-gw-backend-http-settings"
    priority                   = 100
  }
  probe {
    name                                      = "app-gw-health-probe"
    protocol                                  = "Http"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
  }

  depends_on = [
    azurerm_subnet.app_gateway_subnet,
    azurerm_public_ip.app_gw_public_ip
  ]
}