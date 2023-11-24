provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

// Data gathering
data "azurerm_client_config" "current" {}

data "azuread_service_principal" "kv" {
  display_name = "Azure Key Vault"
}

// Basics
locals {
  ressource_nameing = "keyrotationtest1"
  storage_nameing   = "keyrot1test1"
}

// RBAC
// Assign KeyVault Admin Role to current user - needed for manage secrets
resource "azurerm_role_assignment" "keyvault_admin" {
  scope                = azurerm_resource_group.example.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

// Assign Storage Account Key Operator Role to builtin Key Vault service principal - needed for key rotation
resource "azurerm_role_assignment" "storage_account_key_operator_keyvault" {
  scope                = azurerm_resource_group.example.id
  role_definition_name = "Storage Account Key Operator Service Role"
  principal_id         = data.azuread_service_principal.kv.id
}

// Assign Storage Account Key Operator Role to current user - needed for deployment
resource "azurerm_role_assignment" "storage_account_key_operator_user" {
  scope                = azurerm_resource_group.example.id
  role_definition_name = "Storage Account Key Operator Service Role"
  principal_id         = data.azurerm_client_config.current.object_id
}

// Resources

resource "azurerm_resource_group" "example" {
  name     = local.ressource_nameing
  location = "northeurope"
}

resource "azurerm_storage_account" "example" {
  name                     = local.storage_nameing
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_key_vault" "example" {
  name                        = "vault-${local.ressource_nameing}"
  location                    = azurerm_resource_group.example.location
  resource_group_name         = azurerm_resource_group.example.name
  enabled_for_disk_encryption = false
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
  enable_rbac_authorization   = true
}

// KeyVault Operations
// failed first attempt - due to missing permissions - assignment of Key Vault Administrator to current user  solved the issue
resource "azurerm_key_vault_secret" "example" {
  name         = "testkey-${local.ressource_nameing}"
  value        = "meingeheimerkey235"
  key_vault_id = azurerm_key_vault.example.id
  depends_on   = [azurerm_role_assignment.keyvault_admin]
}

// failed with error 403 - assignment of Storage Account Key Operator Role to current user solved the issue
resource "azurerm_key_vault_managed_storage_account" "example" {
  name                         = local.storage_nameing
  key_vault_id                 = azurerm_key_vault.example.id
  storage_account_id           = azurerm_storage_account.example.id
  storage_account_key          = "key1"
  regenerate_key_automatically = true
  regeneration_period          = "P1D"
  depends_on = [
    azurerm_role_assignment.storage_account_key_operator_keyvault, azurerm_role_assignment.storage_account_key_operator_user
  ]
}
