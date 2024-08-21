data "azurerm_client_config" "current_creds" {}

data "azurerm_resource_group" "mgmt_rg" {
  name = "rg-${var.short}-${var.loc}-prd-mgmt"
}

data "azurerm_ssh_public_key" "mgmt_ssh_key" {
  name                = "ssh-${var.short}-${var.loc}-prd-pub-mgmt"
  resource_group_name = data.azurerm_resource_group.mgmt_rg.name
}

data "azurerm_key_vault" "mgmt_kv" {
  name                = "kv-${var.short}-${var.loc}-prd-mgmt-01"
  resource_group_name = data.azurerm_resource_group.mgmt_rg.name
}

data "azurerm_key_vault_secret" "mgmt_local_admin_pwd" {
  key_vault_id = data.azurerm_key_vault.mgmt_kv.id
  name         = "Local${title(var.short)}Admin${title("prd")}Pwd"
}

data "azurerm_user_assigned_identity" "mgmt_user_assigned_id" {
  name                = "id-${var.short}-${var.loc}-prd-mgmt-01"
  resource_group_name = data.azurerm_resource_group.mgmt_rg.name
}