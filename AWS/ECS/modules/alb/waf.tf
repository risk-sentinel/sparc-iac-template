# ===========================================================================
# AWS WAFv2 — edge protection on the public ALB (#578, SC-7 / SI-4)
# ===========================================================================
# The ALB is our internet boundary; without a WAF, scanner/exploit traffic
# reaches SPARC directly. This web ACL inspects inbound requests at the edge.
#
# Rule strategy (see the four rule blocks below):
#   - Always-block regardless of var.waf_block_mode: KnownBadInputs (incl.
#     Log4Shell) + Amazon IP-reputation — zero-false-positive, static override.
#   - Observe-first (COUNT until var.waf_block_mode=true), + the rate rule:
#     CommonRuleSet + SQLi — generic heuristics that can false-positive on a
#     rich app. Prod sets var.waf_block_mode=true (enforce from the start); the
#     module default is false so other envs can observe first.
#   - One permanent per-rule exception (#609): CommonRuleSet's
#     SizeRestrictions_BODY is always COUNT, never BLOCK. It rejects any body
#     over 8 KB, which is every real file upload; see the rule_action_override
#     comment on the CommonRuleSet block for the full rationale.
# Deliberately NO Bot Control (per-request cost; the managed groups + IP
# reputation + rate rule cover the observed scanner/abuse traffic).

locals {
  waf_enabled = var.enable_waf ? 1 : 0
  # The rate rule acts directly (not an override): count vs block.
  waf_rate_count = var.waf_block_mode ? [] : [1]
  waf_rate_block = var.waf_block_mode ? [1] : []
}

# Rule strategy (see the four rule blocks below):
#   Observe-first (COUNT until var.waf_block_mode=true): CommonRuleSet, SQLi —
#     generic heuristics that can false-positive on a rich app, watched first.
#   Always-block (day one): KnownBadInputs (incl. Log4Shell, CVE-2021-44228) and
#     the Amazon IP-reputation list — zero-false-positive, no review window needed.
#   Always-count: CommonRuleSet/SizeRestrictions_BODY (#609) — an 8 KB body cap
#     is incompatible with an artifact-upload application; nginx enforces size.

resource "aws_wafv2_web_acl" "alb" {
  count = local.waf_enabled
  name  = "${local.name_prefix}-alb-waf"
  # WAFv2 description forbids parentheses (^[\w+=:#@/\-,\.\s]+$) — no "(#578)".
  description = "Edge WAF for the ${local.name_prefix} public ALB - see issue 578"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Rate-based rule (priority 0): throttle L7 floods / credential-stuffing from
  # a single IP over a 5-minute window.
  rule {
    name     = "rate-limit"
    priority = 0
    dynamic "action" {
      for_each = local.waf_rate_block
      content {
        block {}
      }
    }
    dynamic "action" {
      for_each = local.waf_rate_count
      content {
        count {}
      }
    }
    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-waf-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # --- Observe-first groups (COUNT until var.waf_block_mode=true) ---
  # Generic heuristics that can false-positive on a rich app; watched first.

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      dynamic "count" {
        for_each = var.waf_block_mode ? [] : [1]
        content {}
      }
      dynamic "none" {
        for_each = var.waf_block_mode ? [1] : []
        content {}
      }
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # SizeRestrictions_BODY counted, not blocked (#609). The rule blocks any
        # request body over 8 KB — WAF's body-inspection ceiling for a REGIONAL
        # (ALB) web ACL. SPARC's core function is uploading compliance artifacts
        # (evidence PDFs, CDEFs, profiles, baselines), so in BLOCK this rule
        # breaks every real upload while adding no inspection coverage: WAF
        # cannot see past 8 KB regardless of the action, and the ceiling only
        # raises to 64 KB (associationConfig), still far under a routine PDF.
        # The enforceable size gate is nginx client_max_body_size 110m plus
        # SPARC's own upload validation. COUNT rather than removal keeps the
        # telemetry — oversize bodies still emit the
        # awswaf:managed:aws:core-rule-set:SizeRestrictions_Body label to the
        # WAF logs, so an anomalous body-size pattern stays observable.
        # Static (not gated on var.waf_block_mode) because the whole group
        # already counts when that flag is false, so the override is a no-op
        # there; keeping it unconditional makes the exception verifiable by
        # inspection, same rationale as the always-block groups below.
        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {}
          }
        }

        # Exempt artifact-upload WRITES from this group entirely (#620).
        #
        # Why: CrossSiteScripting_BODY blocked a real 34 KB evidence upload on
        # 2026-08-03 (POST /evidences, multipart, authenticated browser). Edge
        # blocks leave NO application-side trace, so the user saw neither a
        # success nor a failure — the identical silent-403 signature as #609.
        # #609 counted SizeRestrictions_BODY; the request then simply hit the
        # next rule in the same group. Evidence can be PDF, DOCX, JPEG, XML,
        # JSON or YAML: binary formats contain byte sequences matching XSS and
        # SQLi signatures BY COINCIDENCE, varying per file. That is not a rule
        # to tune — it is a category error to put a content-inspection engine in
        # front of arbitrary binary uploads. Overriding rules one at a time
        # would just queue up the third report.
        #
        # A scope_down_statement narrows WHICH REQUESTS THIS GROUP EVALUATES.
        # It applies to priority 1 ONLY. Still fully enforced on these paths:
        # KnownBadInputs incl. Log4Shell (p2), SQLi (p3), IP reputation (p4),
        # the rate-based rule (p0) — each a separate top-level rule — plus Rails
        # session auth and SPARC's own app-layer upload validation, which is the
        # only layer that can actually decode multipart and check file type.
        #
        # Deliberately path-scoped, NOT content-type-scoped. Excluding
        # `multipart/form-data` globally would be tidier and far worse: an
        # attacker sets that header on any request — /login, password reset —
        # and skips CommonRuleSet everywhere. Path-scoping confines the
        # exposure to endpoints that already require an authenticated session.
        #
        # Writes only. GETs to these paths keep full CommonRuleSet, so
        # reflected-XSS in query strings stays covered; only bodies are exempt.
        #
        # All seven upload families are listed, not just /evidences: they share
        # one failure mode, and six of them were failing silently for the same
        # reason nobody had reported yet.
        scope_down_statement {
          not_statement {
            statement {
              and_statement {
                statement {
                  regex_match_statement {
                    regex_string = "^/(evidences|ssp_documents|sar_documents|sap_documents|poam_documents|profile_documents|cdef_documents)(/|$)"
                    field_to_match {
                      uri_path {}
                    }
                    text_transformation {
                      priority = 0
                      type     = "LOWERCASE"
                    }
                  }
                }
                statement {
                  # POST|PATCH|PUT collapsed into ONE regex leaf. An or_statement
                  # here would exceed the provider's statement-nesting depth
                  # inside scope_down_statement (max 3 levels).
                  regex_match_statement {
                    regex_string = "^(post|patch|put)$"
                    field_to_match {
                      method {}
                    }
                    text_transformation {
                      priority = 0
                      type     = "LOWERCASE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-waf-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3
    override_action {
      dynamic "count" {
        for_each = var.waf_block_mode ? [] : [1]
        content {}
      }
      dynamic "none" {
        for_each = var.waf_block_mode ? [1] : []
        content {}
      }
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-waf-sqli"
      sampled_requests_enabled   = true
    }
  }

  # --- Always-block groups (BLOCK on day one, static override for auditability) ---
  # Zero-false-positive: these patterns never appear in legitimate traffic, so
  # there is no review window to wait for. Static `override_action { none {} }`
  # (block) keeps the Log4Shell protection statically verifiable (CKV_AWS_192).

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet" # incl. Log4Shell JNDI (CVE-2021-44228)
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-waf-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList" # known-malicious source IPs
    priority = 4
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-waf-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-alb-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${local.name_prefix}-alb-waf"
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  count        = local.waf_enabled
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.alb[0].arn
}

# WAF logs → CloudWatch. The log group name MUST start with "aws-waf-logs-".
resource "aws_cloudwatch_log_group" "waf" {
  # Design note (#611) — CKV_AWS_158 (CMK at rest) is a false positive here.
  # Prod sets enable_cmk=true, which populates waf_log_kms_key_arn, so this group
  # IS CMK-encrypted. The ternary below exists only so the module still works in
  # a no-CMK deployment; checkov cannot statically resolve it.
  #
  # This was an inline `checkov:skip` until #611. Inline skips report SKIPPED,
  # which drops the acceptance out of checkov-baseline.yml entirely — no NIST
  # mapping, no reviewer, no cadence, no POA&M line (docs/dev/issue_rules.md).
  # The acceptance now lives in the baseline; the reasoning stays with the code.
  count             = local.waf_enabled
  name              = "aws-waf-logs-${local.name_prefix}"
  retention_in_days = var.waf_log_retention_days
  kms_key_id        = var.waf_log_kms_key_arn != "" ? var.waf_log_kms_key_arn : null

  tags = {
    Name = "${local.name_prefix}-alb-waf-logs"
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "alb" {
  count                   = local.waf_enabled
  resource_arn            = aws_wafv2_web_acl.alb[0].arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]

  # Never log credentials/session material.
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}
