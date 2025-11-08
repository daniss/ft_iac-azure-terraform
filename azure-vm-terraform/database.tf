# Create MySQL flexible server using the key vault secret
resource "azurerm_mysql_flexible_server" "mysql_server" {
  name                   = "${random_pet.prefix.id}-mysql-server"
  location               = azurerm_resource_group.rg.location
  resource_group_name    = azurerm_resource_group.rg.name
  administrator_login    = "mysqladminun"
  administrator_password = random_password.password.result
  version                = "8.0.21"
  sku_name               = "GP_Standard_D2ads_v5"
  high_availability {
    mode = "ZoneRedundant"
  }

  backup_retention_days  = 7

  delegated_subnet_id    = azurerm_subnet.db_subnet.id
  private_dns_zone_id    = azurerm_private_dns_zone.mysql_dns_zone.id

  depends_on = [
    azurerm_subnet.db_subnet,
    azurerm_network_security_group.db_nsg,
    azurerm_private_dns_zone_virtual_network_link.mysql_dns_link
  ]
  
}

resource "azurerm_mysql_flexible_database" "webapp_db" {
  name                = "webapp"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql_server.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}