terraform {
  required_version = ">= 0.12.6"
}

provider "azurerm" {
  version = "~> 2.35.0"
  features {}
}

data "azurerm_client_config" "current" {}

locals {
  diag_key_vault_logs = [
    "AuditEvent",
  ]

  diag_key_vault_metrics = [
    "AllMetrics",
  ]

  diag_resource_list = var.diagnostics != null ? split("/", var.diagnostics.destination) : []
  parsed_diag = var.diagnostics != null ? {
    log_analytics_id   = contains(local.diag_resource_list, "microsoft.operationalinsights") ? var.diagnostics.destination : null
    storage_account_id = contains(local.diag_resource_list, "Microsoft.Storage") ? var.diagnostics.destination : null
    event_hub_auth_id  = contains(local.diag_resource_list, "Microsoft.EventHub") ? var.diagnostics.destination : null
    metric             = contains(var.diagnostics.metrics, "all") ? local.diag_key_vault_metrics : var.diagnostics.metrics
    log                = contains(var.diagnostics.logs, "all") ? local.diag_key_vault_logs : var.diagnostics.logs
    } : {
    log_analytics_id   = null
    storage_account_id = null
    event_hub_auth_id  = null
    metric             = []
    log                = []
  }
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

resource "azurerm_key_vault" "main" {
  name                = format("%s-kv", lower(var.name))
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.sku_name

  enabled_for_deployment          = var.enabled_for_deployment
  enabled_for_disk_encryption     = var.enabled_for_disk_encryption
  enabled_for_template_deployment = var.enabled_for_template_deployment
  soft_delete_enabled             = true
  soft_delete_retention_days      = var.soft_delete_retention_days

  dynamic "network_acls" {
    for_each = var.network_acls != null ? [true] : []
    content {
      bypass                     = var.network_acls.bypass
      default_action             = var.network_acls.default_action
      ip_rules                   = var.network_acls.ip_rules
      virtual_network_subnet_ids = var.network_acls.virtual_network_subnet_ids
    }
  }

  tags = var.tags
}

resource "azurerm_key_vault_access_policy" "main" {
  count        = length(var.access_policies)
  key_vault_id = azurerm_key_vault.main.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = var.access_policies[count.index].object_id

  secret_permissions      = var.access_policies[count.index].secret_permissions
  key_permissions         = var.access_policies[count.index].key_permissions
  certificate_permissions = var.access_policies[count.index].certificate_permissions
  storage_permissions     = var.access_policies[count.index].storage_permissions
}

resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  count                          = var.diagnostics != null ? 1 : 0
  name                           = "${var.name}-ns-diag"
  target_resource_id             = azurerm_key_vault.main.id
  log_analytics_workspace_id     = local.parsed_diag.log_analytics_id
  eventhub_authorization_rule_id = local.parsed_diag.event_hub_auth_id
  eventhub_name                  = local.parsed_diag.event_hub_auth_id != null ? var.diagnostics.eventhub_name : null
  storage_account_id             = local.parsed_diag.storage_account_id

  dynamic "log" {
    for_each = local.parsed_diag.log
    content {
      category = log.value

      retention_policy {
        enabled = false
      }
    }
  }

  dynamic "metric" {
    for_each = local.parsed_diag.metric
    content {
      category = metric.value

      retention_policy {
        enabled = false
      }
    }
  }
}
