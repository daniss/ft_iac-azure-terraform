# Key vault will contain the database credentials
resource "azurerm_key_vault" "kv" {
  name                        = "${random_pet.prefix.id}-kv"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  sku_name                    = "standard"
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  rbac_authorization_enabled  = true
}

resource "azurerm_role_assignment" "kv_admin_management" {
  principal_id   = data.azurerm_client_config.current.object_id
  role_definition_name = "Key Vault Administrator"
  scope          = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "dbPassword"
  value        = random_password.password.result
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
      azurerm_role_assignment.kv_admin_management
  ]
}