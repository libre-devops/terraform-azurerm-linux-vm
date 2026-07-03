terraform {
  # 1.11 floor: the composed ssh-key module uses write-only arguments and ephemeral resources.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.23.0, < 5.0.0"
    }
  }

  backend "azurerm" {}
}
