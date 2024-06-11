data "azurerm_subscription" "primary" {
}

data "azurerm_client_config" "example" {
}


resource "azurerm_user_assigned_identity" "user_managed_identity" {

  name                = "user_managed_identity"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  depends_on          = [azurerm_resource_group.example]
}
resource "azurerm_role_assignment" "example" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.example.object_id
}
resource "azurerm_role_assignment" "kv_user_assigned" {
  scope                = azurerm_key_vault.example.id # Resource ID of the Key Vault
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.example.object_id
}
resource "azurerm_role_assignment" "assigned" {
  scope                = azurerm_key_vault.example.id # Resource ID of the Key Vault
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_user_assigned_identity.user_managed_identity.principal_id
}


