# That is needed for boot diagnostics, which is the concept of capturing serial console output and screenshots of a VM
resource "azurerm_storage_account" "diag_storage" {
  name                     = "diag${random_id.random_id.hex}"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}