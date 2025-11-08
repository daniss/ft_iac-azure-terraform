# That is needed for boot diagnostics, which is the concept of capturing serial console output and screenshots of a VM
resource "azurerm_storage_account" "diag_storage" {
  name                     = "diag${random_id.random_id.hex}"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "artifacts" {
  name                  = "artifacts"
  storage_account_id    = azurerm_storage_account.diag_storage.id
  container_access_type = "private"
}

data "archive_file" "app_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../web-app"
  output_path = "${path.module}/../web-app.zip"
}

resource "azurerm_storage_blob" "app_zip_blob" {
  name                   = "web-app.zip"
  storage_account_name   = azurerm_storage_account.diag_storage.name
  storage_container_name = azurerm_storage_container.artifacts.name
  type                   = "Block"
  source                 = data.archive_file.app_zip.output_path
  depends_on = [
    data.archive_file.app_zip
  ]
}

resource "azurerm_role_assignment" "vmss_blob_reader" {
  scope                = azurerm_storage_account.diag_storage.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_linux_virtual_machine_scale_set.app_vmss.identity[0].principal_id
  
  depends_on = [
    azurerm_linux_virtual_machine_scale_set.app_vmss
  ]
}