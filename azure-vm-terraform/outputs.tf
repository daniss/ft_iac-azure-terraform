output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "public_ip_address_app_gw" {
  value = azurerm_public_ip.app_gw_public_ip.ip_address
}