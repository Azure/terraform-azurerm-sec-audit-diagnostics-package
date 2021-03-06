provider "azurerm" {
  features {}
}

locals {
  prefix              = var.prefix
  suffix              = concat(["diag"], var.suffix)
  resource_group      = var.use_existing_resource_group ? data.azurerm_resource_group.current[0] : azurerm_resource_group.audit_diagnostics_group[0]
}

module "naming" {
  source = "git::https://github.com/Azure/terraform-azurerm-naming"
  suffix = local.suffix
  prefix = local.prefix
}

resource "azurerm_resource_group" "audit_diagnostics_group" {
  name     = module.naming.resource_group.name
  location = var.resource_group_location
  count    = var.use_existing_resource_group ? 0 : 1
}

module "log_analytics" {
  source                                = "git::https://github.com/Azure/terraform-azurerm-sec-log-analytics"
  resource_group_name                   = local.resource_group.name
  resource_group_location               = local.resource_group.location
  prefix                                = local.prefix
  suffix                                = local.suffix
  log_analytics_workspace_sku           = var.log_analytics_workspace_sku
  log_analytics_retention_in_days       = var.log_analytics_retention_in_days
  alternate_automation_account_location = var.automation_account_alternate_location
  automation_account_sku                = var.automation_account_sku
}

module "event_hub" {
  source                  = "git::https://github.com/Azure/terraform-azurerm-sec-event-hub"
  resource_group_name     = local.resource_group.name
  resource_group_location = local.resource_group.location
  prefix                  = local.prefix
  suffix                  = local.suffix
  sku                     = var.event_hub_namespace_sku
  capacity                = var.event_hub_namespace_capacity
  event_hubs              = var.event_hubs
}

module "storage_account" {
  source                               = "git::https://github.com/Azure/terraform-azurerm-sec-storage-account"
  resource_group_name                  = local.resource_group.name
  resource_group_location              = local.resource_group.location
  storage_account_name                 = module.naming.storage_account.name_unique
  storage_account_replication_type     = var.storage_account_replication_type
  allowed_ip_ranges                    = var.allowed_ip_ranges
  permitted_virtual_network_subnet_ids = var.permitted_virtual_network_subnet_ids
  bypass_internal_network_rules        = var.bypass_internal_network_rules
}

resource "azurerm_private_dns_zone" "blob_dns_zone" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = local.resource_group.name
}

resource "azurerm_private_endpoint" "private_endpoint" {
  name                = module.naming.private_endpoint.name
  location            = local.resource_group.location
  resource_group_name = local.resource_group.name
  subnet_id           = var.storage_account_private_endpoint_subnet_id

  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob_dns_zone.id]
  }

  private_service_connection {
    name                           = module.naming.private_service_connection.name
    subresource_names              = ["blob"]
    private_connection_resource_id = module.storage_account.storage_account.id
    is_manual_connection           = false
  }
}

/* resource "azurerm_security_center_workspace" "sc_workspace" {
  scope        = "/subscriptions/${data.azurerm_subscription.current.subscription_id}"
  workspace_id = module.log_analytics.log_analytics_workspace.id
}

resource "azurerm_security_center_subscription_pricing" "sc_sub_pricing" {
  tier = "Standard"
} */