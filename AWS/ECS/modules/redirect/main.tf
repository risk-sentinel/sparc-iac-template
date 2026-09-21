locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# ACM Certificate for the redirect domain
#
# We need a valid TLS cert so the ALB can complete the handshake before
# returning the 301. Without it, browsers see a cert error instead of the
# redirect and never follow it.
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "redirect" {
  domain_name       = var.redirect_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-redirect-cert"
  }
}

resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.redirect.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.redirect_hosted_zone_id
}

resource "aws_acm_certificate_validation" "redirect" {
  certificate_arn         = aws_acm_certificate.redirect.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}

# ---------------------------------------------------------------------------
# Route 53 A record — point the redirect domain at the same ALB
# ---------------------------------------------------------------------------

resource "aws_route53_record" "redirect" {
  zone_id = var.redirect_hosted_zone_id
  name    = var.redirect_domain_name
  type    = "A"

  # Defensive: tolerate the case where a previous apply left the record
  # behind. UPSERT avoids "record already exists" failures during recovery
  # from partial-state scenarios.
  allow_overwrite = true

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = false
  }
}

# ---------------------------------------------------------------------------
# Add the redirect cert to the ALB HTTPS listener as an additional SNI cert
# ---------------------------------------------------------------------------

resource "aws_lb_listener_certificate" "redirect" {
  listener_arn    = var.https_listener_arn
  certificate_arn = aws_acm_certificate_validation.redirect.certificate_arn
}

# ---------------------------------------------------------------------------
# Listener rule — when Host header matches the redirect domain, return a
# 301 redirect to the target domain, preserving path + query string.
# ---------------------------------------------------------------------------

resource "aws_lb_listener_rule" "redirect" {
  listener_arn = var.https_listener_arn
  priority     = var.listener_rule_priority

  action {
    type = "redirect"

    redirect {
      host        = var.target_domain_name
      path        = "/#{path}"
      query       = "#{query}"
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values = [var.redirect_domain_name]
    }
  }

  depends_on = [aws_lb_listener_certificate.redirect]
}
