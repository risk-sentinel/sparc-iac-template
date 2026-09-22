locals {
  name_prefix = "${var.project_name}-${var.environment}"

  gateway_ip_config_name     = "${local.name_prefix}-appgw-ip-config"
  frontend_ip_config_name    = "${local.name_prefix}-appgw-fe-ip"
  frontend_port_https_name   = "${local.name_prefix}-appgw-fe-port-https"
  frontend_port_http_name    = "${local.name_prefix}-appgw-fe-port-http"
  backend_address_pool_name  = "${local.name_prefix}-appgw-be-pool"
  backend_http_settings_name = "${local.name_prefix}-appgw-be-http"
  https_listener_name        = "${local.name_prefix}-appgw-https-listener"
  http_listener_name         = "${local.name_prefix}-appgw-http-listener"
  https_routing_rule_name    = "${local.name_prefix}-appgw-https-rule"
  http_routing_rule_name     = "${local.name_prefix}-appgw-http-rule"
  redirect_config_name       = "${local.name_prefix}-appgw-http-redirect"
  probe_name                 = "${local.name_prefix}-appgw-probe"
  ssl_certificate_name       = "${local.name_prefix}-appgw-ssl-cert"
}

# ---------------------------------------------------------------------------
# Public IP for Application Gateway
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "appgw" {
  name                = "${local.name_prefix}-appgw-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Name = "${local.name_prefix}-appgw-pip"
  }
}

# ---------------------------------------------------------------------------
# Application Gateway (Standard_v2)
# ---------------------------------------------------------------------------

resource "azurerm_application_gateway" "main" {
  name                = "${local.name_prefix}-appgw"
  location            = var.location
  resource_group_name = var.resource_group_name

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = local.gateway_ip_config_name
    subnet_id = var.subnet_id
  }

  # ---------------------------------------------------------------------------
  # Frontend
  # ---------------------------------------------------------------------------

  frontend_ip_configuration {
    name                 = local.frontend_ip_config_name
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = local.frontend_port_https_name
    port = 443
  }

  frontend_port {
    name = local.frontend_port_http_name
    port = 80
  }

  # ---------------------------------------------------------------------------
  # Backend
  # ---------------------------------------------------------------------------

  backend_address_pool {
    name         = local.backend_address_pool_name
    ip_addresses = [var.vm_private_ip]
  }

  backend_http_settings {
    name                  = local.backend_http_settings_name
    cookie_based_affinity = "Disabled"
    port                  = var.app_port
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = local.probe_name
  }

  # ---------------------------------------------------------------------------
  # Health Probe
  # ---------------------------------------------------------------------------

  probe {
    name                = local.probe_name
    host                = "127.0.0.1"
    path                = var.health_check_path
    protocol            = "Http"
    port                = var.app_port
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  # ---------------------------------------------------------------------------
  # HTTPS Listener (443)
  # ---------------------------------------------------------------------------

  http_listener {
    name                           = local.https_listener_name
    frontend_ip_configuration_name = local.frontend_ip_config_name
    frontend_port_name             = local.frontend_port_https_name
    protocol                       = "Https"
    ssl_certificate_name           = var.certificate_data != "" ? local.ssl_certificate_name : null
  }

  # ---------------------------------------------------------------------------
  # HTTP Listener (80)
  # ---------------------------------------------------------------------------

  http_listener {
    name                           = local.http_listener_name
    frontend_ip_configuration_name = local.frontend_ip_config_name
    frontend_port_name             = local.frontend_port_http_name
    protocol                       = "Http"
  }

  # ---------------------------------------------------------------------------
  # Routing — HTTPS -> backend pool
  # ---------------------------------------------------------------------------

  request_routing_rule {
    name                       = local.https_routing_rule_name
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = local.https_listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.backend_http_settings_name
  }

  # ---------------------------------------------------------------------------
  # Routing — HTTP -> HTTPS redirect (301)
  # ---------------------------------------------------------------------------

  request_routing_rule {
    name                        = local.http_routing_rule_name
    priority                    = 200
    rule_type                   = "Basic"
    http_listener_name          = local.http_listener_name
    redirect_configuration_name = local.redirect_config_name
  }

  redirect_configuration {
    name                 = local.redirect_config_name
    redirect_type        = "Permanent"
    target_listener_name = local.https_listener_name
    include_path         = true
    include_query_string = true
  }

  # ---------------------------------------------------------------------------
  # SSL Certificate (if provided)
  # ---------------------------------------------------------------------------

  dynamic "ssl_certificate" {
    for_each = var.certificate_data != "" ? [1] : []
    content {
      name     = local.ssl_certificate_name
      data     = var.certificate_data
      password = var.certificate_password
    }
  }

  tags = {
    Name = "${local.name_prefix}-appgw"
  }
}
