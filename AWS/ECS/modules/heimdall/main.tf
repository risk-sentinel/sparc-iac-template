locals {
  name_prefix       = "${var.project_name}-${var.environment}"
  use_custom_domain = var.domain_name != ""
}

# ---------------------------------------------------------------------------
# ACM Certificate for Heimdall domain
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "heimdall" {
  count             = local.use_custom_domain ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = {
    Name = "${local.name_prefix}-heimdall-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "heimdall_cert_validation" {
  for_each = local.use_custom_domain ? {
    for dvo in aws_acm_certificate.heimdall[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "heimdall" {
  count                   = local.use_custom_domain ? 1 : 0
  certificate_arn         = aws_acm_certificate.heimdall[0].arn
  validation_record_fqdns = [for record in aws_route53_record.heimdall_cert_validation : record.fqdn]
}

# ---------------------------------------------------------------------------
# Route 53 DNS — point heimdall domain to existing ALB
# ---------------------------------------------------------------------------

resource "aws_route53_record" "heimdall" {
  count   = local.use_custom_domain && var.hosted_zone_id != "" ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# ---------------------------------------------------------------------------
# ALB Listener Certificate — Heimdall domain on existing ALB
# All traffic routes through NGINX sidecar (host-based server block).
# No separate target group or listener rule needed.
# ---------------------------------------------------------------------------

resource "aws_lb_listener_certificate" "heimdall" {
  count           = local.use_custom_domain ? 1 : 0
  listener_arn    = var.https_listener_arn
  certificate_arn = aws_acm_certificate_validation.heimdall[0].certificate_arn
}
