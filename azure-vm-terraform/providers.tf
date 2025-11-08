terraform {
  required_version = ">=1.0"

required_providers {
    azurerm = {
        source  = "hashicorp/azurerm"
        version = "~>4.39"
    }
    random = {
        source  = "hashicorp/random"
        version = "~>3.6"
    }
    archive = {
        source  = "hashicorp/archive"
        version = "~>2.7.1"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "680182c5-659b-43f7-b6da-80b3abe9fdea"
}