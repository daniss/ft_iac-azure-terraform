resource "azurerm_log_analytics_workspace" "main" {
  name                = "${random_pet.prefix.id}-logs"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}
resource "azurerm_monitor_diagnostic_setting" "app_gw_logs" {
  name                       = "app-gw-diagnostics"
  target_resource_id         = azurerm_application_gateway.app_gw.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }
  
  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}
resource "azurerm_monitor_diagnostic_setting" "vmss_logs" {
  name                       = "vmss-diagnostics"
  target_resource_id         = azurerm_linux_virtual_machine_scale_set.app_vmss.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  enabled_metric {
    category = "AllMetrics"
  }
}