locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Data Source — existing DNS Zone
# ---------------------------------------------------------------------------

data "azurerm_dns_zone" "main" {
  name                = var.zone_name
  resource_group_name = var.resource_group_name
}

# ---------------------------------------------------------------------------
# DNS A Record
# ---------------------------------------------------------------------------

resource "azurerm_dns_a_record" "main" {
  name                = var.record_name
  zone_name           = data.azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [var.target_ip]

  tags = {
    Name = "${local.name_prefix}-dns-a-record"
  }
}
