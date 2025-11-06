resource "azurerm_resource_group" "rg" {
  location = var.resource_group_location
  name     = "rg-iac1-${random_pet.prefix.id}"
}

data "azurerm_client_config" "current" {}

resource "azurerm_virtual_network" "vnet01" {
  name                = "${random_pet.prefix.id}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "app_gateway_subnet" {
  name                 = "subnet-app-gw"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet01.name
  address_prefixes     = ["10.0.0.0/24"]
  
}

resource "azurerm_subnet" "app_subnet" {
  name                 = "subnet-app"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet01.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "db_subnet" {
  name                 = "subnet-db"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet01.name
  address_prefixes     = ["10.0.2.0/24"]
  delegation {
    name = "mysql-delegation"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_network_security_group" "app_nsg" {
  name                = "${random_pet.prefix.id}-app-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "web"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "10.0.0.0/24"
    destination_address_prefix = "*"
  }
}

# Connect the security group to the subnet; because we are using a VMSS, we associate the NSG to the subnet
resource "azurerm_subnet_network_security_group_association" "app_nsg" {
  subnet_id                 = azurerm_subnet.app_subnet.id
  network_security_group_id = azurerm_network_security_group.app_nsg.id
}

# TODO: Create DB subnet NSG and rules
resource "azurerm_network_security_group" "db_nsg" {
  name                = "${random_pet.prefix.id}-db-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-mysql-from-app-subnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }
}

# Connect the security group to the subnet; because we are using a VMSS, we associate the NSG to the subnet
resource "azurerm_subnet_network_security_group_association" "db_nsg" {
  subnet_id                 = azurerm_subnet.db_subnet.id
  network_security_group_id = azurerm_network_security_group.db_nsg.id
}

# That is needed for boot diagnostics, which is the concept of capturing serial console output and screenshots of a VM
resource "azurerm_storage_account" "diag_storage" {
  name                     = "diag${random_id.random_id.hex}"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_public_ip" "app_gw_public_ip" {
  name                = "${random_pet.prefix.id}-app-gw-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  zones               = ["1", "2", "3"]
  allocation_method   = "Static"
  sku                 = "Standard"
}

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

# We need to add a DNS record for the MySQL server and app
resource "azurerm_private_dns_zone" "mysql_dns_zone" {
  name                = "privatelink.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "mysql_dns_link" {
  name                  = "${random_pet.prefix.id}-mysql-dns-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.mysql_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet01.id
}

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

# Create VMSS
resource "azurerm_linux_virtual_machine_scale_set" "app_vmss" {
  name                = "${random_pet.prefix.id}-vmss"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = var.app_vm_size
  instances           = 2
  admin_username      = "azureuser"
  zones               = ["1", "2"]

  identity {
    type = "SystemAssigned"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal" # change to latest
    sku       = "20_04-lts-gen2"
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

resource "random_id" "random_id" {
  keepers = {
    resource_group = azurerm_resource_group.rg.name
  }

  byte_length = 8
}

resource "random_password" "password" {
  length      = 20
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
  special     = true
}

resource "random_pet" "prefix" {
  prefix = var.prefix
  length = 1
}