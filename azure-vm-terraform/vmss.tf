resource "azurerm_linux_virtual_machine_scale_set" "app_vmss" {
  name                = "${random_pet.prefix.id}-vmss"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = var.app_vm_size
  instances           = 2
  admin_username      = "azureuser"
  zones               = ["1", "2"]
  custom_data = base64encode(templatefile("${path.module}/../cloud-init.tpl", {
    storage_account_name = azurerm_storage_account.diag_storage.name
    mysql_host          = azurerm_mysql_flexible_server.mysql_server.fqdn
    mysql_user          = azurerm_mysql_flexible_server.mysql_server.administrator_login
    mysql_password      = azurerm_mysql_flexible_server.mysql_server.administrator_password
    mysql_database      = "webapp"
  }))

  identity {
    type = "SystemAssigned"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface {
    name    = "${random_pet.prefix.id}-app-nic"
    primary = true

    ip_configuration {
      name                                         = "my_vmss_ip_configuration"
      subnet_id                                    = azurerm_subnet.app_subnet.id
      primary                                      = true
      application_gateway_backend_address_pool_ids = [
        for bap in azurerm_application_gateway.app_gw.backend_address_pool : bap.id
        if bap.name == "app-gw-backend-pool"
      ]
    }
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  depends_on = [
    azurerm_subnet.app_subnet,
    azurerm_storage_account.diag_storage
  ]
}

resource "azurerm_role_assignment" "kv_vmss_reader" {
  role_definition_name = "Key Vault Secrets User"
  scope                = azurerm_key_vault.kv.id
  principal_id         = azurerm_linux_virtual_machine_scale_set.app_vmss.identity[0].principal_id

  depends_on = [
      azurerm_linux_virtual_machine_scale_set.app_vmss
  ]
}

resource "azurerm_monitor_autoscale_setting" "app_vmss_autoscale" {
  name                = "${random_pet.prefix.id}-vmss-autoscale"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.app_vmss.id

  profile {
    name = "AutoScaleProfile"

    capacity {
      minimum = "2"
      maximum = "5"
      default = "2"
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.app_vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.app_vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
  
}