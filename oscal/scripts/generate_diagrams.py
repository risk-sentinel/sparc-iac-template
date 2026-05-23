#!/usr/bin/env python3
"""
Auto-generate Mermaid architecture diagrams from Terraform state JSON.

Parses `terraform show -json` (or `terraform show -json tfplan`) output and
produces a Markdown file containing C4-style Mermaid diagrams that reflect
the actual deployed infrastructure.

Usage:
    python3 oscal/scripts/generate_diagrams.py \
        --state-json state.json \
        --output docs/diagrams/ecs-architecture.md \
        [--pattern ecs|ec2|azure-vm] \
        [--github-step-summary]
"""

import argparse
import json
import os
import sys
from collections import defaultdict, namedtuple
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

Resource = namedtuple("Resource", ["module", "type", "name", "values", "provider"])
Connection = namedtuple("Connection", ["src", "dst", "label", "style"])

# ---------------------------------------------------------------------------
# Resource type registry — maps terraform type → (category, label_template)
#
# label_template may contain {field} placeholders resolved from resource values.
# ---------------------------------------------------------------------------

RESOURCE_REGISTRY = {
    # --- AWS: Networking ---
    "aws_vpc":                          ("networking", "VPC {cidr_block}"),
    "aws_subnet":                       ("networking", "Subnet {cidr_block}"),
    "aws_internet_gateway":             ("networking", "Internet Gateway"),
    "aws_nat_gateway":                  ("networking", "NAT Gateway"),
    "aws_route_table":                  ("networking", "Route Table"),
    "aws_route_table_association":      ("networking", "RT Association"),
    "aws_eip":                          ("networking", "Elastic IP"),
    # --- AWS: Security Groups ---
    "aws_security_group":               ("security_group", "SG: {name}"),
    "aws_security_group_rule":          ("security_group", "SG Rule"),
    # --- AWS: Load Balancer ---
    "aws_lb":                           ("lb", "ALB"),
    "aws_lb_target_group":              ("lb", "Target Group"),
    "aws_lb_listener":                  ("lb", "Listener :{port}"),
    "aws_lb_listener_rule":             ("lb", "Listener Rule"),
    # --- AWS: Compute (ECS) ---
    "aws_ecs_cluster":                  ("compute", "ECS Cluster"),
    "aws_ecs_service":                  ("compute", "ECS Service"),
    "aws_ecs_task_definition":          ("compute", "Fargate Task"),
    "aws_appautoscaling_target":        ("compute", "Autoscaling Target"),
    "aws_appautoscaling_policy":        ("compute", "Autoscaling Policy"),
    # --- AWS: Compute (EC2) ---
    "aws_instance":                     ("compute", "EC2 Instance"),
    "aws_launch_template":              ("compute", "Launch Template"),
    "aws_autoscaling_group":            ("compute", "ASG"),
    # --- AWS: Container Registry ---
    "aws_ecr_repository":               ("registry", "ECR {name}"),
    "aws_ecr_lifecycle_policy":         ("registry", "ECR Lifecycle"),
    # --- AWS: Data ---
    "aws_db_instance":                  ("data", "RDS {engine} {engine_version}"),
    "aws_db_subnet_group":              ("data", "DB Subnet Group"),
    "aws_db_parameter_group":           ("data", "DB Parameter Group"),
    "aws_rds_cluster":                  ("data", "Aurora Cluster"),
    "aws_elasticache_replication_group": ("data", "ElastiCache Redis"),
    "aws_elasticache_subnet_group":     ("data", "Cache Subnet Group"),
    "aws_s3_bucket":                    ("data", "S3 {bucket}"),
    "aws_s3_bucket_versioning":         ("data", "S3 Versioning"),
    "aws_s3_bucket_server_side_encryption_configuration": ("data", "S3 Encryption"),
    "aws_s3_bucket_public_access_block": ("data", "S3 Public Block"),
    "aws_s3_bucket_policy":             ("data", "S3 Policy"),
    "aws_s3_bucket_logging":            ("data", "S3 Logging"),
    # --- AWS: Security / IAM ---
    "aws_iam_role":                     ("security", "IAM Role {name}"),
    "aws_iam_role_policy":              ("security", "IAM Policy"),
    "aws_iam_role_policy_attachment":   ("security", "IAM Attachment"),
    "aws_iam_policy":                   ("security", "IAM Policy {name}"),
    "aws_secretsmanager_secret":        ("security", "Secret {name}"),
    "aws_secretsmanager_secret_version": ("security", "Secret Version"),
    "aws_kms_key":                      ("security", "KMS Key"),
    "aws_kms_alias":                    ("security", "KMS Alias {name}"),
    "aws_acm_certificate":              ("security", "ACM Certificate"),
    "aws_acm_certificate_validation":   ("security", "ACM Validation"),
    # --- AWS: DNS ---
    "aws_route53_record":               ("dns", "DNS {name} ({type})"),
    "aws_route53_zone":                 ("dns", "Hosted Zone {name}"),
    # --- AWS: Monitoring ---
    "aws_cloudwatch_log_group":         ("monitoring", "Log Group {name}"),
    "aws_cloudwatch_metric_alarm":      ("monitoring", "Alarm {alarm_name}"),
    "aws_cloudwatch_dashboard":         ("monitoring", "Dashboard"),
    "aws_sns_topic":                    ("monitoring", "SNS {name}"),
    "aws_sns_topic_subscription":       ("monitoring", "SNS Subscription"),
    "aws_flow_log":                     ("monitoring", "VPC Flow Log"),
    # --- AWS: Logging ---
    "aws_cloudtrail":                   ("monitoring", "CloudTrail"),
    # --- Azure: Networking ---
    "azurerm_virtual_network":          ("networking", "VNet {address_space}"),
    "azurerm_subnet":                   ("networking", "Subnet {name}"),
    "azurerm_network_security_group":   ("security_group", "NSG {name}"),
    "azurerm_network_interface":        ("networking", "NIC"),
    "azurerm_public_ip":                ("networking", "Public IP"),
    # --- Azure: Load Balancer ---
    "azurerm_application_gateway":      ("lb", "App Gateway"),
    # --- Azure: Compute ---
    "azurerm_linux_virtual_machine":    ("compute", "VM {name}"),
    # --- Azure: Data ---
    "azurerm_postgresql_flexible_server": ("data", "PostgreSQL {name}"),
    "azurerm_redis_cache":              ("data", "Redis {name}"),
    "azurerm_storage_account":          ("data", "Storage {name}"),
    "azurerm_storage_container":        ("data", "Blob Container"),
    # --- Azure: Security ---
    "azurerm_key_vault":                ("security", "Key Vault {name}"),
    "azurerm_key_vault_secret":         ("security", "KV Secret"),
    # --- Azure: DNS ---
    "azurerm_dns_a_record":             ("dns", "DNS A {name}"),
    "azurerm_dns_cname_record":         ("dns", "DNS CNAME {name}"),
    # --- Azure: Monitoring ---
    "azurerm_monitor_metric_alert":     ("monitoring", "Alert {name}"),
    "azurerm_monitor_action_group":     ("monitoring", "Action Group"),
}

# Categories for the container diagram layout
CATEGORY_ORDER = [
    "networking", "lb", "compute", "registry", "data",
    "security", "security_group", "dns", "monitoring",
]

CATEGORY_LABELS = {
    "networking":     "Networking",
    "lb":             "Load Balancing",
    "compute":        "Compute",
    "registry":       "Container Registry",
    "data":           "Data Stores",
    "security":       "Security & IAM",
    "security_group": "Security Groups",
    "dns":            "DNS",
    "monitoring":     "Monitoring & Logging",
}

# Mermaid styles matching existing dark-theme convention
CATEGORY_STYLES = {
    "networking":     "fill:#2d4a1a,stroke:#3fb950,color:#c9d1d9",
    "lb":             "fill:#4a3a1a,stroke:#f0883e,color:#c9d1d9",
    "compute":        "fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9",
    "registry":       "fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9",
    "data":           "fill:#4a1a1a,stroke:#f85149,color:#c9d1d9",
    "security":       "fill:#2d333b,stroke:#f0883e,color:#c9d1d9",
    "security_group": "fill:#2d333b,stroke:#58a6ff,color:#c9d1d9",
    "dns":            "fill:#2d333b,stroke:#3fb950,color:#c9d1d9",
    "monitoring":     "fill:#2d333b,stroke:#a371f7,color:#c9d1d9",
}

# Pattern display names
PATTERN_NAMES = {
    "ecs":      "ECS Fargate",
    "ec2":      "EC2",
    "azure-vm": "Azure VM",
}

# ---------------------------------------------------------------------------
# State parsing
# ---------------------------------------------------------------------------


def parse_state(path):
    """Load terraform show -json output."""
    with open(path) as f:
        return json.load(f)


def extract_resources(state):
    """Flatten state JSON into a list of Resource namedtuples."""
    # Handle both terraform show -json (values) and terraform show -json tfplan (planned_values)
    if "planned_values" in state:
        root = state["planned_values"].get("root_module", {})
    elif "values" in state:
        root = state["values"].get("root_module", {})
    else:
        print("Warning: state JSON has neither 'values' nor 'planned_values'", file=sys.stderr)
        return []

    resources = []
    _collect_module_resources(root, "", resources)
    return resources


def _collect_module_resources(module_obj, module_prefix, out):
    """Recursively collect resources from a module and its children."""
    for r in module_obj.get("resources", []):
        provider = r.get("provider_name", r.get("provider", ""))
        out.append(Resource(
            module=module_prefix or "root",
            type=r["type"],
            name=r["name"],
            values=r.get("values", {}),
            provider=provider,
        ))

    for child in module_obj.get("child_modules", []):
        child_addr = child.get("address", "")
        # address is like "module.networking" or "module.kms[0]"
        # Normalize to just the module name
        mod_name = child_addr.replace("module.", "").split("[")[0]
        if "." in mod_name:
            # nested module — keep full path
            mod_name = child_addr.replace("module.", "")
        _collect_module_resources(child, mod_name, out)


# ---------------------------------------------------------------------------
# Classification & connection detection
# ---------------------------------------------------------------------------


def classify_resources(resources):
    """Group resources by category using the registry."""
    classified = defaultdict(list)
    for r in resources:
        entry = RESOURCE_REGISTRY.get(r.type)
        if entry:
            category = entry[0]
            classified[category].append(r)
        # Resources not in registry are silently skipped
    return dict(classified)


def make_label(resource):
    """Build a display label for a resource from the registry template."""
    entry = RESOURCE_REGISTRY.get(resource.type)
    if not entry:
        return f"{resource.type}.{resource.name}"
    template = entry[1]
    try:
        label = template.format(**resource.values)
    except (KeyError, IndexError):
        # Missing field in values — use template as-is, stripping placeholders
        import re
        label = re.sub(r"\{[^}]+\}", "", template).strip()
    # Truncate long labels
    if len(label) > 60:
        label = label[:57] + "..."
    return label


def make_node_id(resource):
    """Create a unique Mermaid node ID for a resource."""
    # Use module + type + name, sanitized for Mermaid
    raw = f"{resource.module}_{resource.type}_{resource.name}"
    return "".join(c if c.isalnum() else "_" for c in raw)


def detect_pattern(resources):
    """Auto-detect the infrastructure pattern from resource types."""
    types = {r.type for r in resources}
    if "aws_ecs_cluster" in types or "aws_ecs_service" in types:
        return "ecs"
    if "aws_instance" in types or "aws_launch_template" in types:
        return "ec2"
    if any(t.startswith("azurerm_") for t in types):
        return "azure-vm"
    # Default to checking provider
    providers = {r.provider for r in resources}
    if any("azure" in p for p in providers):
        return "azure-vm"
    return "ecs"  # fallback


def detect_connections(resources):
    """Detect connections between resources by inspecting attribute values."""
    connections = []
    # Build lookup: resource id/arn → Resource
    id_to_resource = {}
    for r in resources:
        vals = r.values
        for key in ("id", "arn"):
            val = vals.get(key)
            if val and isinstance(val, str):
                id_to_resource[val] = r

    # Build module → resources mapping
    module_resources = defaultdict(list)
    for r in resources:
        module_resources[r.module].append(r)

    # Detect SG chain from security group rules
    sg_map = {}  # sg id → Resource
    for r in resources:
        if r.type == "aws_security_group":
            sg_id = r.values.get("id")
            if sg_id:
                sg_map[sg_id] = r

    for r in resources:
        if r.type == "aws_security_group":
            for direction in ("ingress", "egress"):
                rules = r.values.get(direction, [])
                if not isinstance(rules, list):
                    continue
                for rule in rules:
                    if not isinstance(rule, dict):
                        continue
                    src_sgs = rule.get("security_groups", [])
                    if not isinstance(src_sgs, list):
                        continue
                    port = rule.get("from_port", "?")
                    to_port = rule.get("to_port", "?")
                    port_label = str(port) if port == to_port else f"{port}-{to_port}"
                    proto = rule.get("protocol", "tcp")
                    for src_sg_id in src_sgs:
                        src_r = sg_map.get(src_sg_id)
                        if src_r:
                            connections.append(Connection(
                                src=src_r, dst=r,
                                label=f":{port_label} {proto}",
                                style="-->",
                            ))

        # Detect SG rules as separate resources
        if r.type == "aws_security_group_rule":
            src_sg = r.values.get("source_security_group_id")
            dst_sg = r.values.get("security_group_id")
            if src_sg and dst_sg and src_sg in sg_map and dst_sg in sg_map:
                port = r.values.get("from_port", "?")
                to_port = r.values.get("to_port", "?")
                port_label = str(port) if port == to_port else f"{port}-{to_port}"
                connections.append(Connection(
                    src=sg_map[src_sg], dst=sg_map[dst_sg],
                    label=f":{port_label}",
                    style="-->",
                ))

    # Detect cross-module references via ARN/ID scanning
    for r in resources:
        _scan_values_for_refs(r, r.values, id_to_resource, connections)

    return _deduplicate_connections(connections)


def _scan_values_for_refs(source_resource, values, id_to_resource, connections):
    """Scan resource values for ARN/ID references to other resources."""
    if not isinstance(values, dict):
        return
    for key, val in values.items():
        if key in ("id", "arn", "tags", "tags_all"):
            continue
        if isinstance(val, str) and val in id_to_resource:
            target = id_to_resource[val]
            if target.module != source_resource.module or target.name != source_resource.name:
                connections.append(Connection(
                    src=source_resource, dst=target,
                    label="", style="-->",
                ))
        elif isinstance(val, list):
            for item in val:
                if isinstance(item, str) and item in id_to_resource:
                    target = id_to_resource[item]
                    if target.module != source_resource.module:
                        connections.append(Connection(
                            src=source_resource, dst=target,
                            label="", style="-->",
                        ))
                elif isinstance(item, dict):
                    _scan_values_for_refs(source_resource, item, id_to_resource, connections)
        elif isinstance(val, dict):
            _scan_values_for_refs(source_resource, val, id_to_resource, connections)


def _deduplicate_connections(connections):
    """Remove duplicate connections (same src+dst pair)."""
    seen = set()
    deduped = []
    for c in connections:
        key = (make_node_id(c.src), make_node_id(c.dst))
        reverse_key = (key[1], key[0])
        if key not in seen and reverse_key not in seen:
            seen.add(key)
            deduped.append(c)
    return deduped


# ---------------------------------------------------------------------------
# Module dependency detection
# ---------------------------------------------------------------------------


def detect_module_dependencies(resources):
    """Detect dependencies between Terraform modules.

    Returns a list of (src_module, dst_module) tuples where src depends on dst.
    """
    # Build module → set of all IDs/ARNs produced
    module_outputs = defaultdict(set)  # module → set of id/arn values
    id_to_module = {}  # id/arn value → module name

    for r in resources:
        mod = r.module
        for key in ("id", "arn"):
            val = r.values.get(key)
            if val and isinstance(val, str):
                module_outputs[mod].add(val)
                id_to_module[val] = mod

    # Scan each resource's values for references to other modules' outputs
    deps = set()
    for r in resources:
        _find_module_refs(r.module, r.values, id_to_module, deps)

    return sorted(deps)


def _find_module_refs(source_module, values, id_to_module, deps):
    """Recursively scan values for references to other modules."""
    if isinstance(values, str):
        target_mod = id_to_module.get(values)
        if target_mod and target_mod != source_module:
            deps.add((source_module, target_mod))
    elif isinstance(values, dict):
        for k, v in values.items():
            if k in ("id", "arn", "tags", "tags_all"):
                continue
            _find_module_refs(source_module, v, id_to_module, deps)
    elif isinstance(values, list):
        for item in values:
            _find_module_refs(source_module, item, id_to_module, deps)


# ---------------------------------------------------------------------------
# Subnet / VPC grouping helpers
# ---------------------------------------------------------------------------


def get_vpc_info(resources):
    """Extract VPC CIDR from resources."""
    for r in resources:
        if r.type in ("aws_vpc", "azurerm_virtual_network"):
            cidr = r.values.get("cidr_block", "")
            if not cidr:
                addr_space = r.values.get("address_space", [])
                cidr = addr_space[0] if addr_space else ""
            return cidr
    return ""


def classify_subnets(resources):
    """Classify subnets as public or private based on tags/name."""
    public = []
    private = []
    for r in resources:
        if r.type not in ("aws_subnet", "azurerm_subnet"):
            continue
        tags = r.values.get("tags", {}) or {}
        name = tags.get("Name", r.values.get("name", r.name)).lower()
        cidr = r.values.get("cidr_block", r.values.get("address_prefixes", [""])[0] if isinstance(r.values.get("address_prefixes"), list) else "")
        if "public" in name:
            public.append(cidr)
        else:
            private.append(cidr)
    return public, private


# ---------------------------------------------------------------------------
# Diagram generators
# ---------------------------------------------------------------------------


def _esc(text):
    """Escape text for Mermaid labels."""
    return text.replace('"', "'").replace("\n", " ")


def generate_system_context(resources, pattern):
    """Generate C4 Level 1 System Context diagram."""
    cloud = "AWS" if pattern != "azure-vm" else "Azure"
    region = ""
    for r in resources:
        if r.type == "aws_vpc":
            # Region comes from provider, not resource — use a sensible default
            region = "us-east-1"
            break
        if r.type == "azurerm_virtual_network":
            region = r.values.get("location", "")
            break

    pattern_label = PATTERN_NAMES.get(pattern, pattern.upper())

    # Check for DNS records to determine domain
    domain = ""
    for r in resources:
        if r.type == "aws_route53_record":
            domain = r.values.get("name", "")
            if domain:
                break
        if r.type in ("azurerm_dns_a_record", "azurerm_dns_cname_record"):
            domain = r.values.get("fqdn", r.values.get("name", ""))
            if domain:
                break

    # Check for IdP integrations (secrets with OIDC/LDAP references)
    has_oidc = any(
        "oidc" in r.name.lower() or "oidc" in str(r.values.get("name", "")).lower()
        for r in resources
    )
    has_github = any(
        "github" in r.name.lower() or "github" in str(r.values.get("name", "")).lower()
        for r in resources if r.type == "aws_secretsmanager_secret"
    )

    lines = [
        "## System Context (C4 Level 1)",
        "",
        "```mermaid",
        "graph TB",
        '    User[/"Users<br/>(Browser)"/]',
        '    Admin[/"Admin<br/>(GitHub Actions)"/]',
    ]

    if has_oidc:
        lines.append('    IdP["OIDC Identity Provider"]')
    if has_github:
        lines.append('    GitHub["GitHub<br/>(OAuth)"]')

    lines.append("")
    cloud_label = f"{cloud} ({region})" if region else cloud
    lines.append(f'    subgraph Cloud["{cloud_label}"]')
    lines.append(f'        SPARC["SPARC Platform<br/>({pattern_label})"]')
    lines.append("    end")
    lines.append("")
    lines.append("    User -->|HTTPS| SPARC")
    lines.append("    Admin -->|CI/CD Deploy| SPARC")
    if has_oidc:
        lines.append("    User -->|MFA| IdP")
        lines.append("    IdP -->|JWT| SPARC")
    if has_github:
        lines.append("    User -->|OAuth| GitHub")
        lines.append("    GitHub -->|Token| SPARC")

    lines.append("")
    lines.append("    style Cloud fill:#232f3e,stroke:#ff9900,color:#fff")
    lines.append("    style SPARC fill:#1f6feb,stroke:#58a6ff,color:#fff")
    lines.append("```")

    return "\n".join(lines)


def generate_container_diagram(resources, classified, connections, pattern):
    """Generate C4 Level 2 Container diagram with VPC/subnet nesting."""
    cloud = "AWS" if pattern != "azure-vm" else "Azure"
    region = ""
    for r in resources:
        if r.type == "aws_vpc":
            region = "us-east-1"
            break
        if r.type == "azurerm_virtual_network":
            region = r.values.get("location", "")
            break

    vpc_cidr = get_vpc_info(resources)
    public_subnets, private_subnets = classify_subnets(resources)

    lines = [
        "## Container Diagram (C4 Level 2)",
        "",
        "```mermaid",
        "graph TB",
        '    Internet["Internet"]',
        "",
    ]

    cloud_label = f"{cloud} ({region})" if region else cloud
    lines.append(f'    subgraph Cloud["{cloud_label}"]')

    # VPC subgraph
    vpc_label = f"VPC {vpc_cidr}" if vpc_cidr else "VPC"
    lines.append(f'        subgraph VPC["{vpc_label}"]')

    # Public subnets
    if public_subnets:
        pub_label = "Public Subnets"
        lines.append(f'            subgraph Public["{pub_label}"]')
        # Place LB and NAT in public
        for r in classified.get("lb", []):
            if r.type in ("aws_lb", "azurerm_application_gateway"):
                nid = make_node_id(r)
                label = _build_lb_label(r)
                lines.append(f'                {nid}["{_esc(label)}"]')
        for r in resources:
            if r.type == "aws_nat_gateway":
                nid = make_node_id(r)
                lines.append(f'                {nid}["NAT Gateway"]')
        lines.append("            end")

    # Private subnets
    if private_subnets:
        lines.append(f'            subgraph Private["Private Subnets"]')
        # Place compute resources
        for r in classified.get("compute", []):
            if r.type in ("aws_ecs_cluster", "aws_ecs_service", "aws_ecs_task_definition",
                          "aws_instance", "azurerm_linux_virtual_machine"):
                nid = make_node_id(r)
                label = make_label(r)
                lines.append(f'                {nid}["{_esc(label)}"]')
        # Place data resources
        for r in classified.get("data", []):
            if r.type in ("aws_db_instance", "aws_rds_cluster",
                          "aws_elasticache_replication_group",
                          "azurerm_postgresql_flexible_server",
                          "azurerm_redis_cache"):
                nid = make_node_id(r)
                label = make_label(r)
                lines.append(f'                {nid}[("{_esc(label)}")]')
        lines.append("            end")

    lines.append("        end")  # VPC

    # Services outside VPC but inside cloud
    outside_vpc_types = {
        "dns": ("aws_route53_record", "aws_route53_zone",
                "azurerm_dns_a_record", "azurerm_dns_cname_record"),
        "security": ("aws_acm_certificate", "aws_secretsmanager_secret",
                     "aws_kms_key", "azurerm_key_vault"),
        "registry": ("aws_ecr_repository",),
        "data": ("aws_s3_bucket", "azurerm_storage_account"),
        "monitoring": ("aws_cloudwatch_metric_alarm", "aws_cloudwatch_dashboard",
                       "aws_sns_topic", "azurerm_monitor_metric_alert"),
    }

    outside_resources = []
    for cat, types in outside_vpc_types.items():
        for r in classified.get(cat, []):
            if r.type in types:
                outside_resources.append(r)

    if outside_resources:
        lines.append("")
        for r in outside_resources:
            nid = make_node_id(r)
            label = make_label(r)
            lines.append(f'        {nid}["{_esc(label)}"]')

    lines.append("    end")  # Cloud
    lines.append("")

    # Draw key connections
    lines.extend(_generate_container_connections(resources, classified, connections))

    # Styles
    lines.append("")
    lines.append("    style Cloud fill:#232f3e,stroke:#ff9900,color:#fff")
    lines.append("    style VPC fill:#1a2332,stroke:#58a6ff,color:#c9d1d9")
    if public_subnets:
        lines.append("    style Public fill:#2d4a1a,stroke:#3fb950,color:#c9d1d9")
    if private_subnets:
        lines.append("    style Private fill:#4a1a1a,stroke:#f85149,color:#c9d1d9")

    lines.append("```")
    return "\n".join(lines)


def _build_lb_label(r):
    """Build a descriptive label for a load balancer."""
    if r.type == "aws_lb":
        return "Application Load Balancer<br/>:443 HTTPS / :80 redirect"
    if r.type == "azurerm_application_gateway":
        return "Application Gateway"
    return make_label(r)


def _generate_container_connections(resources, classified, connections):
    """Generate connection arrows for the container diagram."""
    lines = []

    # Find key resources by type for semantic connections
    alb = dns = ecs = rds = s3 = secrets = ecr = nat = cw = sns = None
    for r in resources:
        if r.type == "aws_lb":
            alb = r
        elif r.type in ("aws_route53_record", "azurerm_dns_a_record"):
            dns = dns or r
        elif r.type in ("aws_ecs_service", "aws_ecs_cluster"):
            ecs = ecs or r
        elif r.type in ("aws_db_instance", "aws_rds_cluster",
                        "azurerm_postgresql_flexible_server"):
            rds = rds or r
        elif r.type in ("aws_s3_bucket", "azurerm_storage_account"):
            s3 = s3 or r
        elif r.type == "aws_secretsmanager_secret":
            secrets = secrets or r
        elif r.type == "aws_ecr_repository":
            ecr = ecr or r
        elif r.type == "aws_nat_gateway":
            nat = r
        elif r.type in ("aws_cloudwatch_metric_alarm", "aws_cloudwatch_dashboard"):
            cw = cw or r
        elif r.type == "aws_sns_topic":
            sns = sns or r

    # Semantic connection arrows
    if dns and alb:
        lines.append(f"    Internet -->|DNS| {make_node_id(dns)}")
        lines.append(f"    {make_node_id(dns)} -->|Alias| {make_node_id(alb)}")
    elif alb:
        lines.append(f"    Internet -->|HTTPS| {make_node_id(alb)}")

    if alb and ecs:
        lines.append(f"    {make_node_id(alb)} -->|:8080| {make_node_id(ecs)}")
    elif alb:
        # Find first compute resource
        for r in classified.get("compute", []):
            lines.append(f"    {make_node_id(alb)} --> {make_node_id(r)}")
            break

    if ecs and rds:
        lines.append(f"    {make_node_id(ecs)} -->|:5432 SSL| {make_node_id(rds)}")
    if ecs and s3:
        lines.append(f"    {make_node_id(ecs)} -->|IAM role| {make_node_id(s3)}")
    if ecs and secrets:
        lines.append(f"    {make_node_id(ecs)} -->|GetSecretValue| {make_node_id(secrets)}")
    if ecs and ecr:
        lines.append(f"    {make_node_id(ecs)} -->|Pull images| {make_node_id(ecr)}")
    if ecs and nat:
        lines.append(f"    {make_node_id(ecs)} -->|Outbound| {make_node_id(nat)}")
    if cw and sns:
        lines.append(f"    {make_node_id(cw)} -->|Alerts| {make_node_id(sns)}")
    if rds and cw:
        lines.append(f"    {make_node_id(rds)} -.->|Metrics| {make_node_id(cw)}")
    if ecs and cw:
        lines.append(f"    {make_node_id(ecs)} -.->|Logs + Metrics| {make_node_id(cw)}")

    return lines


def generate_network_topology(resources, connections):
    """Generate security group chain / network topology diagram."""
    # Collect security groups
    sgs = [r for r in resources if r.type in ("aws_security_group",
                                               "azurerm_network_security_group")]
    if not sgs:
        return ""

    lines = [
        "## Security Architecture",
        "",
        "```mermaid",
        "graph LR",
    ]

    # Build SG subgraph with ingress rules
    lines.append('    subgraph Network["Network Security"]')
    for sg in sgs:
        nid = make_node_id(sg)
        label = make_label(sg)
        # Extract ingress rules summary
        ingress = sg.values.get("ingress", [])
        rule_summary = _summarize_sg_rules(ingress)
        if rule_summary:
            label += f"<br/>{rule_summary}"
        lines.append(f'        {nid}["{_esc(label)}"]')
    lines.append("    end")

    # Draw SG chain connections (only SG-to-SG, not resource-to-SG refs)
    sg_types = ("aws_security_group", "aws_security_group_rule",
                "azurerm_network_security_group")
    sg_connections = [c for c in connections
                      if c.src.type in sg_types and c.dst.type in sg_types
                      and c.label]  # Only labeled connections (port rules)

    seen = set()
    for c in sg_connections:
        src_id = make_node_id(c.src)
        dst_id = make_node_id(c.dst)
        key = (src_id, dst_id)
        if key not in seen:
            seen.add(key)
            lines.append(f"    {src_id} -->|{_esc(c.label)}| {dst_id}")

    # Collect secrets and IAM info
    secrets = [r for r in resources if r.type in ("aws_secretsmanager_secret",
                                                   "azurerm_key_vault_secret",
                                                   "azurerm_key_vault")]
    iam_roles = [r for r in resources if r.type == "aws_iam_role"]
    monitors = [r for r in resources
                if r.type in ("aws_cloudwatch_metric_alarm", "aws_flow_log",
                              "aws_cloudwatch_dashboard")]

    if secrets:
        lines.append("")
        lines.append('    subgraph Secrets["Secrets Management"]')
        for s in secrets[:6]:  # Limit to avoid diagram clutter
            nid = make_node_id(s)
            label = make_label(s)
            lines.append(f'        {nid}["{_esc(label)}"]')
        lines.append("    end")

    if monitors:
        lines.append("")
        lines.append('    subgraph Monitoring["Monitoring"]')
        for m in monitors[:6]:
            nid = make_node_id(m)
            label = make_label(m)
            lines.append(f'        {nid}["{_esc(label)}"]')
        lines.append("    end")

    # Styles
    lines.append("")
    lines.append("    style Network fill:#2d333b,stroke:#58a6ff,color:#c9d1d9")
    if secrets:
        lines.append("    style Secrets fill:#2d333b,stroke:#f0883e,color:#c9d1d9")
    if monitors:
        lines.append("    style Monitoring fill:#2d333b,stroke:#a371f7,color:#c9d1d9")

    lines.append("```")
    return "\n".join(lines)


def _summarize_sg_rules(rules):
    """Summarize ingress rules into a compact label."""
    if not isinstance(rules, list):
        return ""
    parts = []
    for rule in rules[:4]:  # Limit display
        if not isinstance(rule, dict):
            continue
        from_port = rule.get("from_port", 0)
        to_port = rule.get("to_port", 0)
        cidrs = rule.get("cidr_blocks", [])
        sgs = rule.get("security_groups", [])

        port_str = str(from_port) if from_port == to_port else f"{from_port}-{to_port}"

        if sgs:
            parts.append(f"IN: {port_str} from SG")
        elif cidrs:
            cidr_str = ", ".join(str(c) for c in cidrs[:2])
            parts.append(f"IN: {port_str} from {cidr_str}")

    return "<br/>".join(parts)


def generate_module_dependency(resources):
    """Generate module dependency graph from cross-module references."""
    deps = detect_module_dependencies(resources)
    modules = sorted({r.module for r in resources if r.module != "root"})

    if not modules:
        return ""

    lines = [
        "## Module Dependency Graph",
        "",
        "```mermaid",
        "graph TD",
    ]

    # Module category for coloring
    module_categories = {
        "networking": "networking",
        "ecr": "registry",
        "acm": "security",
        "kms": "security",
        "s3": "data",
        "secrets": "security",
        "iam": "security",
        "rds": "data",
        "alb": "lb",
        "logging": "monitoring",
        "route53": "dns",
        "ecs_fargate": "compute",
        "ecs": "compute",
        "heimdall": "compute",
        "elasticache": "data",
        "sns": "monitoring",
        "cloudwatch": "monitoring",
    }

    for mod in modules:
        # Count resources in this module
        count = sum(1 for r in resources if r.module == mod)
        mod_id = "".join(c if c.isalnum() else "_" for c in mod)
        lines.append(f'    {mod_id}["{mod}<br/>({count} resources)"]')

    lines.append("")

    for src, dst in deps:
        src_id = "".join(c if c.isalnum() else "_" for c in src)
        dst_id = "".join(c if c.isalnum() else "_" for c in dst)
        lines.append(f"    {dst_id} --> {src_id}")

    # Apply styles based on module category
    lines.append("")
    for mod in modules:
        mod_id = "".join(c if c.isalnum() else "_" for c in mod)
        # Match module name to category
        base_mod = mod.split(".")[-1].split("[")[0]
        cat = module_categories.get(base_mod, "compute")
        style = CATEGORY_STYLES.get(cat, "fill:#2d333b,stroke:#8b949e,color:#c9d1d9")
        lines.append(f"    style {mod_id} {style}")

    lines.append("```")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Document assembly
# ---------------------------------------------------------------------------


def assemble_document(diagrams, pattern, resource_count, connection_count):
    """Combine diagrams into a single markdown document."""
    pattern_label = PATTERN_NAMES.get(pattern, pattern.upper())
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    sections = [
        f"# SPARC {pattern_label} — Architecture Diagram",
        "",
    ]

    for diagram in diagrams:
        if diagram:
            sections.append(diagram)
            sections.append("")

    sections.append("---")
    sections.append(
        f"*Auto-generated from Terraform state on {timestamp}. "
        f"{resource_count} resources, {connection_count} connections detected. "
        f"Do not edit manually.*"
    )
    sections.append("")

    return "\n".join(sections)


# ---------------------------------------------------------------------------
# GitHub Step Summary
# ---------------------------------------------------------------------------


def write_step_summary(content):
    """Write content to GitHub Actions step summary."""
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        print("Warning: GITHUB_STEP_SUMMARY not set, skipping", file=sys.stderr)
        return
    with open(summary_path, "a") as f:
        f.write(content)
        f.write("\n")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Generate Mermaid architecture diagrams from Terraform state JSON."
    )
    parser.add_argument(
        "--state-json", required=True,
        help="Path to terraform show -json output",
    )
    parser.add_argument(
        "--output", required=True,
        help="Output markdown file path (e.g. docs/diagrams/ecs-architecture.md)",
    )
    parser.add_argument(
        "--pattern", choices=["ecs", "ec2", "azure-vm"],
        help="Infrastructure pattern (auto-detected if omitted)",
    )
    parser.add_argument(
        "--github-step-summary", action="store_true",
        help="Write diagrams to GitHub Actions step summary",
    )
    args = parser.parse_args()

    # Parse state
    state = parse_state(args.state_json)
    resources = extract_resources(state)

    if not resources:
        print("Warning: no resources found in state JSON", file=sys.stderr)
        sys.exit(0)

    # Detect pattern
    pattern = args.pattern or detect_pattern(resources)
    print(f"Pattern: {pattern}", file=sys.stderr)

    # Classify and detect connections
    classified = classify_resources(resources)
    connections = detect_connections(resources)

    total_resources = len(resources)
    total_connections = len(connections)

    print(f"Resources: {total_resources}", file=sys.stderr)
    print(f"Connections: {total_connections}", file=sys.stderr)
    for cat in CATEGORY_ORDER:
        count = len(classified.get(cat, []))
        if count:
            print(f"  {CATEGORY_LABELS.get(cat, cat)}: {count}", file=sys.stderr)

    # Generate diagrams
    diagrams = [
        generate_system_context(resources, pattern),
        generate_container_diagram(resources, classified, connections, pattern),
        generate_network_topology(resources, connections),
        generate_module_dependency(resources),
    ]

    # Assemble document
    doc = assemble_document(diagrams, pattern, total_resources, total_connections)

    # Write output
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w") as f:
        f.write(doc)
    print(f"Wrote {args.output}", file=sys.stderr)

    # GitHub step summary
    if args.github_step_summary:
        write_step_summary(doc)
        print("Wrote GitHub step summary", file=sys.stderr)


if __name__ == "__main__":
    main()
