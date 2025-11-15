resource "azurerm_linux_virtual_machine_scale_set" "app_vmss" {
  name                = "${random_pet.prefix.id}-vmss"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = local.app_vm_size
  instances           = 2
  admin_username      = "azureuser"
  zones               = ["1", "2"]
  custom_data = base64encode(templatefile("${path.module}/../cloud-init.tpl", {
    storage_account_name = azurerm_storage_account.diag_storage.name
    mysql_host          = azurerm_mysql_flexible_server.mysql_server.fqdn
    mysql_user          = azurerm_mysql_flexible_server.mysql_server.administrator_login
    mysql_database      = "webapp"
    kv_name             = azurerm_key_vault.kv.name
    kv_secret_name      = azurerm_key_vault_secret.db_password.name
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
    public_key = local.public_key_ssh
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

resource "azurerm_portal_dashboard" "main" {
  name                = "${random_pet.prefix.id}-dashboard"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  
  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = {
          "0" = {
            position = {
              x        = 0
              y        = 0
              colSpan  = 6
              rowSpan  = 4
            }
            metadata = {
              inputs = [
                {
                  name = "options"
                  isOptional = true
                },
                {
                  name = "sharedTimeRange"
                  isOptional = true
                }
              ]
              type = "Extension/HubsExtension/PartType/MonitorChartPart"
              settings = {
                content = {
                  options = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = {
                            id = azurerm_application_gateway.app_gw.id
                          }
                          name = "Throughput"
                          aggregationType = 4
                          namespace = "microsoft.network/applicationgateways"
                          metricVisualization = {
                            displayName = "Throughput"
                          }
                        }
                      ]
                      title = "Application Gateway - Throughput"
                      titleKind = 2
                      visualization = {
                        chartType = 2
                        legendVisualization = {
                          isVisible = true
                          position = 2
                          hideSubtitle = false
                        }
                        axisVisualization = {
                          x = {
                            isVisible = true
                            axisType = 2
                          }
                          y = {
                            isVisible = true
                            axisType = 1
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          "1" = {
            position = {
              x        = 6
              y        = 0
              colSpan  = 6
              rowSpan  = 4
            }
            metadata = {
              inputs = [
                {
                  name = "options"
                  isOptional = true
                },
                {
                  name = "sharedTimeRange"
                  isOptional = true
                }
              ]
              type = "Extension/HubsExtension/PartType/MonitorChartPart"
              settings = {
                content = {
                  options = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = {
                            id = azurerm_application_gateway.app_gw.id
                          }
                          name = "UnhealthyHostCount"
                          aggregationType = 4
                          namespace = "microsoft.network/applicationgateways"
                          metricVisualization = {
                            displayName = "Unhealthy Host Count"
                          }
                        }
                      ]
                      title = "Application Gateway - Unhealthy Hosts"
                      titleKind = 2
                      visualization = {
                        chartType = 2
                        legendVisualization = {
                          isVisible = true
                          position = 2
                          hideSubtitle = false
                        }
                        axisVisualization = {
                          x = {
                            isVisible = true
                            axisType = 2
                          }
                          y = {
                            isVisible = true
                            axisType = 1
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          "2" = {
            position = {
              x        = 0
              y        = 4
              colSpan  = 6
              rowSpan  = 4
            }
            metadata = {
              inputs = [
                {
                  name = "options"
                  isOptional = true
                },
                {
                  name = "sharedTimeRange"
                  isOptional = true
                }
              ]
              type = "Extension/HubsExtension/PartType/MonitorChartPart"
              settings = {
                content = {
                  options = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = {
                            id = azurerm_linux_virtual_machine_scale_set.app_vmss.id
                          }
                          name = "Percentage CPU"
                          aggregationType = 4
                          namespace = "microsoft.compute/virtualmachinescalesets"
                          metricVisualization = {
                            displayName = "Percentage CPU"
                          }
                        }
                      ]
                      title = "VMSS - CPU Usage"
                      titleKind = 2
                      visualization = {
                        chartType = 2
                        legendVisualization = {
                          isVisible = true
                          position = 2
                          hideSubtitle = false
                        }
                        axisVisualization = {
                          x = {
                            isVisible = true
                            axisType = 2
                          }
                          y = {
                            isVisible = true
                            axisType = 1
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          "3" = {
            position = {
              x        = 6
              y        = 4
              colSpan  = 6
              rowSpan  = 4
            }
            metadata = {
              inputs = [
                {
                  name = "options"
                  isOptional = true
                },
                {
                  name = "sharedTimeRange"
                  isOptional = true
                }
              ]
              type = "Extension/HubsExtension/PartType/MonitorChartPart"
              settings = {
                content = {
                  options = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = {
                            id = azurerm_application_gateway.app_gw.id
                          }
                          name = "ResponseStatus"
                          aggregationType = 1
                          namespace = "microsoft.network/applicationgateways"
                          metricVisualization = {
                            displayName = "Response Status"
                          }
                        }
                      ]
                      title = "Application Gateway - Response Status"
                      titleKind = 2
                      visualization = {
                        chartType = 2
                        legendVisualization = {
                          isVisible = true
                          position = 2
                          hideSubtitle = false
                        }
                        axisVisualization = {
                          x = {
                            isVisible = true
                            axisType = 2
                          }
                          y = {
                            isVisible = true
                            axisType = 1
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          "4" = {
            position = {
              x        = 0
              y        = 8
              colSpan  = 6
              rowSpan  = 4
            }
            metadata = {
              inputs = [
                {
                  name = "options"
                  isOptional = true
                },
                {
                  name = "sharedTimeRange"
                  isOptional = true
                }
              ]
              type = "Extension/HubsExtension/PartType/MonitorChartPart"
              settings = {
                content = {
                  options = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = {
                            id = azurerm_mysql_flexible_server.mysql_server.id
                          }
                          name = "cpu_percent"
                          aggregationType = 4
                          namespace = "microsoft.dbformysql/flexibleservers"
                          metricVisualization = {
                            displayName = "CPU Percent"
                          }
                        }
                      ]
                      title = "MySQL - CPU Usage"
                      titleKind = 2
                      visualization = {
                        chartType = 2
                        legendVisualization = {
                          isVisible = true
                          position = 2
                          hideSubtitle = false
                        }
                        axisVisualization = {
                          x = {
                            isVisible = true
                            axisType = 2
                          }
                          y = {
                            isVisible = true
                            axisType = 1
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          "5" = {
            position = {
              x        = 6
              y        = 8
              colSpan  = 6
              rowSpan  = 4
            }
            metadata = {
              inputs = [
                {
                  name = "options"
                  isOptional = true
                },
                {
                  name = "sharedTimeRange"
                  isOptional = true
                }
              ]
              type = "Extension/HubsExtension/PartType/MonitorChartPart"
              settings = {
                content = {
                  options = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = {
                            id = azurerm_mysql_flexible_server.mysql_server.id
                          }
                          name = "active_connections"
                          aggregationType = 4
                          namespace = "microsoft.dbformysql/flexibleservers"
                          metricVisualization = {
                            displayName = "Active Connections"
                          }
                        }
                      ]
                      title = "MySQL - Active Connections"
                      titleKind = 2
                      visualization = {
                        chartType = 2
                        legendVisualization = {
                          isVisible = true
                          position = 2
                          hideSubtitle = false
                        }
                        axisVisualization = {
                          x = {
                            isVisible = true
                            axisType = 2
                          }
                          y = {
                            isVisible = true
                            axisType = 1
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    metadata = {
      model = {
        timeRange = {
          value = {
            relative = {
              duration = 24
              timeUnit = 1
            }
          }
          type = "MsPortalFx.Composition.Configuration.ValueTypes.TimeRange"
        }
      }
    }
  })
}

resource "azurerm_monitor_metric_alert" "vmss_cpu_alert" {
  name                = "vmss-high-cpu-alert"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_virtual_machine_scale_set.app_vmss.id]
  
  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.app_gw_action_group.id
  }
}