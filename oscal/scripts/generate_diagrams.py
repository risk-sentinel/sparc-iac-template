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
import re
import sys
from collections import defaultdict, namedtuple
from datetime import datetime, timezone

# Mermaid syntax fragments reused across the diagram builders (S1192, #526).
_MERMAID_FENCE = "```mermaid"
_MERMAID_END = "    end"
_GRAPH_LR = "graph LR"

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

Resource = namedtuple("Resource", ["module", "type", "name", "values", "provider"])

# Connection carries the visual edge (src/dst/label/style) plus optional
# enrichment data used by the Boundary Reference table and labeled arrows.
# The trailing fields default to None so the legacy 4-arg positional form
# Connection(src, dst, label, style) keeps working at every existing call site.
Connection = namedtuple(
    "Connection",
    ["src", "dst", "label", "style", "port", "protocol", "tls",
     "src_sg", "dst_sg", "arn_template", "iam_action"],
    defaults=[None, None, None, None, None, None, None],
)

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
    """Load terraform show -json output.

    Fails loudly (non-zero exit) with a clear message rather than a bare
    traceback when the file is missing, empty, or not valid JSON — e.g. a
    truncated `terraform show -json` dump or stderr/warnings contaminating the
    capture (#358).
    """
    try:
        with open(path) as f:
            text = f.read()
    except OSError as e:
        print(f"ERROR: cannot read state JSON '{path}': {e}", file=sys.stderr)
        sys.exit(1)
    if not text.strip():
        print(f"ERROR: state JSON '{path}' is empty — "
              f"terraform show -json produced no output", file=sys.stderr)
        sys.exit(1)
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        print(f"ERROR: state JSON '{path}' is not valid JSON: {e} "
              f"(check for warnings/stderr leaking into the capture)", file=sys.stderr)
        sys.exit(1)


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


def detect_connections(resources):  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
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
                        if src_r and src_r is not r:  # skip self-referential rules
                            connections.append(Connection(
                                src=src_r, dst=r,
                                label=f":{port_label} {proto}",
                                style="-->",
                                port=port_label, protocol=proto,
                                src_sg=make_label(src_r), dst_sg=make_label(r),
                            ))

        # Detect SG rules as separate resources
        if r.type == "aws_security_group_rule":
            src_sg = r.values.get("source_security_group_id")
            dst_sg = r.values.get("security_group_id")
            if src_sg and dst_sg and src_sg in sg_map and dst_sg in sg_map and src_sg != dst_sg:
                port = r.values.get("from_port", "?")
                to_port = r.values.get("to_port", "?")
                port_label = str(port) if port == to_port else f"{port}-{to_port}"
                proto = r.values.get("protocol", "tcp")
                connections.append(Connection(
                    src=sg_map[src_sg], dst=sg_map[dst_sg],
                    label=f":{port_label}",
                    style="-->",
                    port=port_label, protocol=proto,
                    src_sg=make_label(sg_map[src_sg]), dst_sg=make_label(sg_map[dst_sg]),
                ))

    # Detect cross-module references via ARN/ID scanning
    for r in resources:
        _scan_values_for_refs(r, r.values, id_to_resource, connections)

    return _deduplicate_connections(connections)


def _scan_values_for_refs(source_resource, values, id_to_resource, connections):  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
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
# Enrichment extraction — ports, protocols, TLS, ARN templates, IAM actions
#
# These pure functions derive the connection-level data points an architect or
# 3PAO auditor needs (SC-7 boundary protection) directly from the parsed state.
# Each returns a plain lookup dict so the diagram generators can join against
# them with graceful fallback when a data point is absent.
# ---------------------------------------------------------------------------

# arn:partition:service:region:account-id:resource — collapse the volatile
# account-id and region tokens to placeholders. Anchored on the surrounding
# colons so 12-digit substrings inside a resource name are never clobbered.
_ACCOUNT_RE = re.compile(r"(?<=:)\d{12}(?=:)")
_REGION_RE = re.compile(
    r"(?<=:)(us|eu|ap|sa|ca|me|af|il)-(north|south|east|west|central|northeast|"
    r"southeast|northwest|southwest)-\d(?=:)"
)


def template_arn(arn):
    """Replace account-id and region in an ARN with <account>/<region>."""
    if not isinstance(arn, str) or not arn.startswith("arn:"):
        return arn
    arn = _ACCOUNT_RE.sub("<account>", arn)
    arn = _REGION_RE.sub("<region>", arn)
    return arn


def abbreviate_arn(arn):
    """Short, account/region-free form for inline arrow labels.

    arn:aws:secretsmanager:us-east-1:123:secret:example-* -> secret:example-*
    arn:aws:s3:::example-uploads                          -> example-uploads
    """
    if not isinstance(arn, str) or not arn.startswith("arn:"):
        return arn
    parts = arn.split(":", 5)  # partition, service, region, account, resource
    resource = parts[5] if len(parts) == 6 else parts[-1]
    # S3 resources have no resource-type prefix; keep the bucket/key tail.
    return resource


def _as_list(x):
    """Normalize an IAM Action/Resource that may be a str, list, or absent."""
    if x is None:
        return []
    return x if isinstance(x, list) else [x]


def extract_sg_flows(resources):  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
    """Map (src_sg_id, dst_sg_id) -> {port, protocol} from SG rules.

    Covers both inline aws_security_group ingress/egress and standalone
    aws_security_group_rule resources. Self-referential rules are skipped.
    """
    flows = {}

    def _port_label(frm, to):
        return str(frm) if frm == to else f"{frm}-{to}"

    for r in resources:
        if r.type == "aws_security_group":
            sg_id = r.values.get("id")
            for direction in ("ingress", "egress"):
                for rule in r.values.get(direction, []) or []:
                    if not isinstance(rule, dict):
                        continue
                    proto = rule.get("protocol", "tcp")
                    port = _port_label(rule.get("from_port", "?"),
                                       rule.get("to_port", "?"))
                    for peer in rule.get("security_groups", []) or []:
                        if peer == sg_id:
                            continue
                        src, dst = (peer, sg_id) if direction == "ingress" else (sg_id, peer)
                        flows[(src, dst)] = {"port": port, "protocol": proto}
        elif r.type == "aws_security_group_rule":
            src = r.values.get("source_security_group_id")
            dst = r.values.get("security_group_id")
            if src and dst and src != dst:
                flows[(src, dst)] = {
                    "port": _port_label(r.values.get("from_port", "?"),
                                        r.values.get("to_port", "?")),
                    "protocol": r.values.get("protocol", "tcp"),
                }
    return flows


def _tls_from_ssl_policy(policy):
    """Translate an ALB ssl_policy into a short TLS label, or None."""
    if not policy:
        return None
    if "TLS13" in policy or "TLS-1-2" in policy or "TLS13-1-2" in policy:
        return "TLS1.2+"
    return "TLS"


def extract_listener_map(resources):
    """Map an ALB's node id -> {port, protocol, tls} for the forward listener.

    The :80 redirect listener is annotation only; only a `forward` listener
    represents real downstream traffic, so it wins when present.
    """
    lb_by_arn = {r.values.get("arn"): r
                 for r in resources if r.type == "aws_lb" and r.values.get("arn")}
    out = {}
    for lis in resources:
        if lis.type != "aws_lb_listener":
            continue
        v = lis.values
        lb = lb_by_arn.get(v.get("load_balancer_arn"))
        if not lb:
            continue
        actions = v.get("default_action", []) or []
        atypes = {a.get("type") for a in actions if isinstance(a, dict)}
        is_forward = "forward" in atypes
        key = make_node_id(lb)
        meta = {
            "port": v.get("port"),
            "protocol": v.get("protocol"),
            "tls": _tls_from_ssl_policy(v.get("ssl_policy")),
            "is_forward": is_forward,
        }
        # Prefer a forward listener; otherwise keep whatever we have so the
        # edge-facing (Internet -> ALB) label still renders.
        if key not in out or (is_forward and not out[key].get("is_forward")):
            out[key] = meta
    return out


def extract_datastore_tls(resources):  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
    """Map a data-store node id -> 'TLS' when transit encryption is enforced.

    RDS: an aws_db_parameter_group with rds.force_ssl=1 attached to the
    instance. ElastiCache: transit_encryption_enabled=true (rediss://).
    """
    forced_pgs = set()
    for pg in resources:
        if pg.type != "aws_db_parameter_group":
            continue
        for p in pg.values.get("parameter", []) or []:
            if (isinstance(p, dict) and p.get("name") == "rds.force_ssl"
                    and str(p.get("value")) == "1"):
                forced_pgs.add(pg.values.get("name"))
                break

    tls = {}
    for r in resources:
        if ((r.type == "aws_db_instance"
                and r.values.get("parameter_group_name") in forced_pgs)
                or (r.type == "aws_elasticache_replication_group"
                    and r.values.get("transit_encryption_enabled") is True)):
            tls[make_node_id(r)] = "TLS"
    return tls


def extract_task_containers(resources):  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
    """Parse aws_ecs_task_definition container_definitions into C4 containers.

    Returns a list of {name, image, ports:[int,...]} dicts in definition order.
    Returns [] when no task definition parses (EC2/Azure/partial state) so the
    data-plane diagram falls back to a single ECS Service node.
    """
    containers = []
    for r in resources:
        if r.type != "aws_ecs_task_definition":
            continue
        raw = r.values.get("container_definitions")
        if isinstance(raw, str):
            try:
                defs = json.loads(raw)
            except (json.JSONDecodeError, TypeError):
                continue
        elif isinstance(raw, list):
            defs = raw
        else:
            continue
        for cd in defs if isinstance(defs, list) else []:
            if not isinstance(cd, dict):
                continue
            ports = []
            for pm in cd.get("portMappings", []) or []:
                if isinstance(pm, dict) and pm.get("containerPort") is not None:
                    ports.append(pm["containerPort"])
            containers.append({
                "name": cd.get("name", "container"),
                "image": cd.get("image", ""),
                "ports": ports,
            })
    return containers


def extract_iam_statements(resources):  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
    """Flatten Allow statements from inline IAM policies.

    Returns a list of {owner, actions, resources (templated), raw_resources}.
    Handles str-or-list Action/Resource, single-dict Statement, and skips
    Deny / NotAction statements (cannot be summarized as a grant).
    """
    out = []
    for r in resources:
        if r.type not in ("aws_iam_role_policy", "aws_iam_policy"):
            continue
        doc = r.values.get("policy")
        if isinstance(doc, str):
            try:
                doc = json.loads(doc)
            except (json.JSONDecodeError, TypeError):
                continue
        if not isinstance(doc, dict):
            continue
        stmts = doc.get("Statement", [])
        if isinstance(stmts, dict):
            stmts = [stmts]
        for st in stmts if isinstance(stmts, list) else []:
            if not isinstance(st, dict) or st.get("Effect") != "Allow":
                continue
            if "Action" not in st:  # NotAction — not a summarizable grant
                continue
            raw_res = _as_list(st.get("Resource"))
            out.append({
                "owner": r.name,
                "actions": _as_list(st.get("Action")),
                "resources": [template_arn(a) for a in raw_res],
                "raw_resources": raw_res,
            })
    return out


def _arn_glob_match(pattern, arn):
    """Match an IAM resource pattern (with * and ?) against a concrete ARN."""
    if not isinstance(pattern, str) or not isinstance(arn, str):
        return False
    if pattern == "*":
        return True
    rx = "^" + re.escape(pattern).replace(r"\*", ".*").replace(r"\?", ".") + "$"
    return re.match(rx, arn) is not None


def _shorten_actions(actions):
    """Compact an action list to a single readable token.

    secretsmanager:GetSecretValue            -> GetSecretValue
    [GetSecretValue, DescribeSecret, ...]    -> GetSecretValue +2
    """
    if not actions:
        return None
    first = actions[0].split(":", 1)[-1]
    extra = len(actions) - 1
    return f"{first} +{extra}" if extra > 0 else first


# Map a data-store resource type to the IAM service prefix that acts on it, so
# a broad `Resource: "*"` grant for an unrelated service (e.g. xray, logs) does
# not get mis-attributed to the store.
_TARGET_SERVICE = {
    "aws_secretsmanager_secret": "secretsmanager",
    "aws_s3_bucket": "s3",
    "aws_ecr_repository": "ecr",
    "aws_kms_key": "kms",
}


def iam_summary_for(target_resource, statements):  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
    """Find the IAM grant a component holds over target_resource.

    Returns (short_action, templated_arn, abbreviated_arn). Among all Allow
    statements whose Resource pattern matches the target's ARN, prefer those
    whose actions belong to the target's own service (a `Resource: "*"` xray or
    logs grant matches every ARN but is not a grant *over this store*), then
    prefer the most specific ARN pattern. Returns (None, None, None) when no
    service-relevant grant is found.
    """
    target_arn = target_resource.values.get("arn") if target_resource else None
    if not target_arn:
        return None, None, None
    svc = _TARGET_SERVICE.get(target_resource.type)

    best = None  # (relevant, specificity, actions, tmpl, pat)
    for st in statements:
        for pat, tmpl in zip(st["raw_resources"], st["resources"]):
            if not _arn_glob_match(pat, target_arn):
                continue
            relevant_actions = [a for a in st["actions"]
                                if svc and a.split(":", 1)[0] == svc]
            relevant = bool(relevant_actions)
            if pat == "*":
                specificity = 0
            elif "*" in pat:
                specificity = 1
            else:
                specificity = 2
            actions = relevant_actions if relevant else st["actions"]
            cand = (relevant, specificity, actions, tmpl, pat)
            if best is None or (cand[0], cand[1]) > (best[0], best[1]):
                best = cand

    # Only assert a grant we can attribute to the target's own service.
    if best is None or (svc and not best[0]):
        return None, None, None
    _relevant, _spec, actions, tmpl, pat = best
    table_arn = tmpl if pat != "*" else template_arn(target_arn)
    return _shorten_actions(actions), table_arn, abbreviate_arn(target_arn)


def collapse_group(resources, noun, threshold=3):
    """Render a category as individual nodes, or one summary node if numerous.

    Returns a list of (node_id, label) tuples. When the count exceeds the
    threshold the group collapses to a single 'Noun (N nouns)' node keyed by a
    stable synthetic id, keeping each diagram bite legible.
    """
    if not resources:
        return []
    if len(resources) > threshold:
        nid = "grp_" + "".join(c if c.isalnum() else "_" for c in noun.lower())
        return [(nid, f"{noun} ({len(resources)})")]
    return [(make_node_id(r), make_label(r)) for r in resources]


def _edge_label(*, protocol=None, port=None, tls=None, action=None,
                arn_abbrev=None, fallback=""):
    """Compose an enriched Mermaid edge label, falling back when data is absent.

    Examples: 'HTTPS:443 TLS1.2+', ':8080', 'PostgreSQL:5432 TLS',
    'GetSecretValue<br/>secret:example-*'.
    """
    parts = []
    if protocol and port:
        parts.append(f"{protocol}:{port}")
    elif port:
        parts.append(f":{port}")
    if tls:
        parts.append(tls)
    base = " ".join(parts)
    if action:
        base = f"{action} {base}".strip() if base else action
        if arn_abbrev:
            base += f"<br/>{arn_abbrev}"
    return base or fallback


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


def generate_system_context(resources, pattern):  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
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
        _MERMAID_FENCE,
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
    lines.append(_MERMAID_END)
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


def _region_for(resources):
    """Best-effort region label for the cloud subgraph header."""
    for r in resources:
        if r.type == "aws_vpc":
            return "us-east-1"
        if r.type == "azurerm_virtual_network":
            return r.values.get("location", "")
    return ""


def _build_lb_label(r, listener_map=None):
    """Build a descriptive label for a load balancer, using real listener data."""
    if r.type == "aws_lb":
        meta = (listener_map or {}).get(make_node_id(r))
        if meta and meta.get("port"):
            tls = f" {meta['tls']}" if meta.get("tls") else ""
            proto = meta.get("protocol") or "HTTPS"
            return f"Application Load Balancer<br/>{proto}:{meta['port']}{tls}"
        return "Application Load Balancer<br/>:443 HTTPS / :80 redirect"
    if r.type == "azurerm_application_gateway":
        return "Application Gateway"
    return make_label(r)


def _pick_containers(containers):  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
    """Classify parsed task containers into (proxy, app, heimdall) roles."""
    proxy = app = heimdall = None
    nodes = {}
    for c in containers:
        cid = "task_" + "".join(ch if ch.isalnum() else "_" for ch in c["name"])
        nodes[cid] = c
        low = c["name"].lower()
        if "nginx" in low or 8080 in c["ports"]:
            proxy = proxy or (cid, c)
        elif "heimdall" in low:
            heimdall = heimdall or (cid, c)
        else:
            app = app or (cid, c)
    if proxy is None and nodes:
        first_id = next(iter(nodes))
        proxy = (first_id, nodes[first_id])
    if app is None:
        for cid, c in nodes.items():
            if not (proxy and cid == proxy[0]):
                app = (cid, c)
                break
    return proxy, app, heimdall, nodes


def generate_dataplane_flow(resources, classified, pattern, listener_map,  # NOSONAR S1172/S3776 — `classified` kept for signature parity with the sibling generate_* builders (all take the classified map); complexity is inherent to the multi-tier flow layout and test-covered (#526)
                            containers, datastore_tls):
    """C4 L2 data-plane bite: Internet -> ALB -> task containers -> RDS/Redis.

    Edges carry real port/protocol/TLS. Falls back to a single ECS Service node
    (and the legacy literal labels) when container_definitions can't be parsed.
    """
    cloud = "AWS" if pattern != "azure-vm" else "Azure"
    region = _region_for(resources)
    vpc_cidr = get_vpc_info(resources)

    alb = next((r for r in resources
                if r.type in ("aws_lb", "azurerm_application_gateway")), None)
    nat = next((r for r in resources if r.type == "aws_nat_gateway"), None)
    rds = next((r for r in resources if r.type in
                ("aws_db_instance", "aws_rds_cluster",
                 "azurerm_postgresql_flexible_server")), None)
    redis = next((r for r in resources if r.type in
                  ("aws_elasticache_replication_group", "azurerm_redis_cache")), None)
    ecs = next((r for r in resources if r.type in
                ("aws_ecs_service", "aws_ecs_cluster", "aws_instance",
                 "azurerm_linux_virtual_machine")), None)

    lines = [
        "## Data-Plane Flow (C4 Level 2)",
        "",
        _MERMAID_FENCE,
        "graph TB",
        '    Internet["Internet"]',
        "",
    ]
    cloud_label = f"{cloud} ({region})" if region else cloud
    lines.append(f'    subgraph Cloud["{cloud_label}"]')
    vpc_label = f"VPC {vpc_cidr}" if vpc_cidr else "VPC"
    lines.append(f'        subgraph VPC["{vpc_label}"]')

    # Public subnet: ALB + NAT
    if alb or nat:
        lines.append('            subgraph Public["Public Subnets"]')
        if alb:
            lines.append(f'                {make_node_id(alb)}["{_esc(_build_lb_label(alb, listener_map))}"]')
        if nat:
            lines.append(f'                {make_node_id(nat)}["NAT Gateway"]')
        lines.append("            end")

    # Private subnet: task containers + data stores
    lines.append('            subgraph Private["Private Subnets"]')
    proxy = app = heimdall = None
    if containers:
        proxy, app, heimdall, nodes = _pick_containers(containers)
        lines.append('                subgraph Task["ECS Fargate Task"]')
        for cid, c in nodes.items():
            ports = ("<br/>:" + ", :".join(str(p) for p in c["ports"])) if c["ports"] else ""
            lines.append(f'                    {cid}["{_esc(c["name"])}{ports}"]')
        lines.append("                end")
    elif ecs:
        lines.append(f'                {make_node_id(ecs)}["{_esc(make_label(ecs))}"]')
    for store in (rds, redis):
        if store:
            lines.append(f'                {make_node_id(store)}[("{_esc(make_label(store))}")]')
    lines.append("            end")
    lines.append("        end")  # VPC
    lines.append(_MERMAID_END)  # Cloud
    lines.append("")

    # ---- edges ----
    alb_meta = listener_map.get(make_node_id(alb)) if alb else None

    if alb:
        lbl = _edge_label(protocol=(alb_meta or {}).get("protocol"),
                          port=(alb_meta or {}).get("port"),
                          tls=(alb_meta or {}).get("tls"), fallback="HTTPS")
        lines.append(f"    Internet -->|{_esc(lbl)}| {make_node_id(alb)}")

    if alb and proxy:
        pport = proxy[1]["ports"][0] if proxy[1]["ports"] else None
        lines.append(f"    {make_node_id(alb)} -->|{_esc(_edge_label(protocol='HTTP', port=pport, fallback=':8080'))}| {proxy[0]}")
    elif alb and ecs:
        lines.append(f"    {make_node_id(alb)} -->|:8080| {make_node_id(ecs)}")

    if proxy and app:
        aport = app[1]["ports"][0] if app[1]["ports"] else None
        lines.append(f"    {proxy[0]} -->|{_esc(_edge_label(protocol='HTTP', port=aport, fallback=':3000'))} localhost| {app[0]}")
    if proxy and heimdall:
        hport = heimdall[1]["ports"][0] if heimdall[1]["ports"] else None
        lines.append(f"    {proxy[0]} -->|{_esc(_edge_label(protocol='HTTP', port=hport, fallback=':3001'))} localhost| {heimdall[0]}")

    if app:
        db_src = app[0]
    elif ecs:
        db_src = make_node_id(ecs)
    else:
        db_src = None
    if db_src and rds:
        lbl = _edge_label(protocol="PostgreSQL", port=5432,
                          tls=datastore_tls.get(make_node_id(rds)), fallback=":5432 SSL")
        lines.append(f"    {db_src} -->|{_esc(lbl)}| {make_node_id(rds)}")
    if db_src and redis:
        lbl = _edge_label(protocol="Redis", port=6379,
                          tls=datastore_tls.get(make_node_id(redis)), fallback=":6379")
        lines.append(f"    {db_src} -->|{_esc(lbl)}| {make_node_id(redis)}")
    if db_src and nat:
        lines.append(f"    {db_src} -->|egress :443| {make_node_id(nat)}")

    # Styles
    lines.append("")
    lines.append("    style Cloud fill:#232f3e,stroke:#ff9900,color:#fff")
    lines.append("    style VPC fill:#1a2332,stroke:#58a6ff,color:#c9d1d9")
    if alb or nat:
        lines.append("    style Public fill:#2d4a1a,stroke:#3fb950,color:#c9d1d9")
    lines.append("    style Private fill:#4a1a1a,stroke:#f85149,color:#c9d1d9")
    if containers:
        lines.append("    style Task fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9")
    lines.append("```")
    return "\n".join(lines)


def generate_data_access(resources, iam_statements):
    """C4 bite: ECS task role access to S3 / Secrets / ECR with IAM grants.

    Each group is collapsed when numerous; edges carry the IAM action and an
    abbreviated (account/region-free) ARN. Returns '' when nothing applies.
    """
    ecs = next((r for r in resources if r.type in
                ("aws_ecs_service", "aws_ecs_cluster")), None)
    secrets = [r for r in resources if r.type == "aws_secretsmanager_secret"]
    buckets = [r for r in resources if r.type == "aws_s3_bucket"]
    repos = [r for r in resources if r.type == "aws_ecr_repository"]
    if not ecs or not (secrets or buckets or repos):
        return ""

    eid = make_node_id(ecs)
    lines = [
        "## Data & Secrets Access",
        "",
        _MERMAID_FENCE,
        _GRAPH_LR,
        f'    {eid}["ECS Task Role"]',
        "",
    ]

    for noun, rs in (("Secrets Manager", secrets), ("S3 Buckets", buckets),
                     ("ECR Repos", repos)):
        if not rs:
            continue
        if len(rs) > 3:
            # Collapsed group: one node, a representative action, no per-ARN.
            nid = "grp_" + "".join(c if c.isalnum() else "_" for c in noun.lower())
            lines.append(f'    {nid}["{_esc(noun)} ({len(rs)})"]')
            action = next((a for a in (iam_summary_for(r, iam_statements)[0]
                                       for r in rs) if a), None)
            lines.append(f"    {eid} -->|{_esc(_edge_label(action=action, fallback='IAM role'))}| {nid}")
        else:
            # Few resources: an accurate per-resource action + abbreviated ARN.
            for r in rs:
                nid = make_node_id(r)
                lines.append(f'    {nid}["{_esc(make_label(r))}"]')
                action, _tmpl, arn = iam_summary_for(r, iam_statements)
                lbl = _edge_label(action=action, arn_abbrev=arn, fallback="IAM role")
                lines.append(f"    {eid} -->|{_esc(lbl)}| {nid}")

    lines.append("")
    lines.append(f"    style {eid} fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9")
    lines.append("```")
    return "\n".join(lines)


def generate_observability(resources):
    """Collapsed monitoring bite: CloudWatch (N alarms) -> SNS, Flow Logs."""
    alarms = [r for r in resources if r.type == "aws_cloudwatch_metric_alarm"]
    dash = [r for r in resources if r.type == "aws_cloudwatch_dashboard"]
    flow = [r for r in resources if r.type == "aws_flow_log"]
    sns = [r for r in resources if r.type == "aws_sns_topic"]
    if not (alarms or dash or flow or sns):
        return ""

    lines = ["## Observability", "", _MERMAID_FENCE, _GRAPH_LR]
    if alarms:
        lines.append(f'    obs_alarms["CloudWatch ({len(alarms)} alarms)"]')
    if dash:
        lines.append('    obs_dash["CloudWatch Dashboard"]')
    if flow:
        flabel = f"VPC Flow Logs ({len(flow)})" if len(flow) > 1 else "VPC Flow Logs"
        lines.append(f'    obs_flow["{flabel}"]')
    sns_nodes = collapse_group(sns, "SNS Topics")
    for snid, label in sns_nodes:
        lines.append(f'    {snid}["{_esc(label)}"]')

    if alarms and sns_nodes:
        for snid, _ in sns_nodes:
            lines.append(f"    obs_alarms -->|Notify| {snid}")

    lines.append("```")
    return "\n".join(lines)


def _clean_sg(sg_label):
    """'SG: example-rds-sg-2026...' -> 'example-rds-sg' for the table."""
    s = sg_label.replace("SG: ", "")
    return re.sub(r"-?\d{6,}.*$", "", s).rstrip("-")  # NOSONAR S8786 — bounded short SG label; ".*$" always matches, so no catastrophic-backtracking path (#526)


def _md_escape(text):
    """Escape a value for a Markdown table cell."""
    return str(text).replace("|", "\\|").replace("\n", " ")


def generate_boundary_reference(resources, connections, listener_map,  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
                                datastore_tls, iam_statements):
    """Printable boundary table (FedRAMP SC-7): every inter-component edge."""
    rows = []  # (src_dst, port, proto, tls, sg_pair, arn, action)

    rds_tls = any(r.type == "aws_db_instance" and make_node_id(r) in datastore_tls
                  for r in resources)
    redis_tls = any(r.type == "aws_elasticache_replication_group"
                    and make_node_id(r) in datastore_tls for r in resources)

    # Public ingress (ALB listener)
    for r in resources:
        if r.type == "aws_lb":
            meta = listener_map.get(make_node_id(r))
            if meta and meta.get("port"):
                rows.append(("Internet → ALB", str(meta["port"]),
                             meta.get("protocol") or "—", meta.get("tls") or "—",
                             "0.0.0.0/0 → ALB SG", "—", "—"))

    # Network boundaries (SG flows)
    for c in connections:
        if not (c.port and c.src_sg and c.dst_sg):
            continue
        tls = "—"
        if ((str(c.port) == "5432" and rds_tls)
                or (str(c.port) == "6379" and redis_tls)):
            tls = "TLS"
        rows.append((f"{_clean_sg(c.src_sg)} → {_clean_sg(c.dst_sg)}", str(c.port),
                     c.protocol or "—", tls, f"{c.src_sg} → {c.dst_sg}", "—", "—"))

    # Data access (IAM grants over data stores)
    for r in resources:
        if r.type in ("aws_secretsmanager_secret", "aws_s3_bucket",
                      "aws_ecr_repository"):
            action, tmpl, _ = iam_summary_for(r, iam_statements)
            if action:
                rows.append((f"ECS Task → {make_label(r)}", "—", "—", "—", "—",
                             tmpl or "—", action))

    if not rows:
        return ""

    rows = sorted(set(rows))
    header = (
        "## Boundary Reference (FedRAMP SC-7)\n\n"
        "| Source → Dest | Port | Protocol | TLS | Source SG → Dest SG "
        "| ARN Template | IAM Action |\n"
        "| --- | --- | --- | --- | --- | --- | --- |"
    )
    body = "\n".join("| " + " | ".join(_md_escape(x) for x in row) + " |"
                     for row in rows)
    return header + "\n" + body


# ---------------------------------------------------------------------------
# Machine-readable boundary export (Phase B / #347)
#
# Emits the same data the Boundary Reference table renders, but as a stable
# JSON keyed by an SSP-component title substring so assemble_ssp.py can attach
# native OSCAL protocols[]/port-ranges[] + props[] to the matching components.
# ---------------------------------------------------------------------------

# Logical component -> (terraform types, SSP component title substring, protocol name).
# title-match is matched (case-insensitive substring) against the CDEF-derived
# SSP component titles, e.g. "AWS Application Load Balancer", "AWS RDS PostgreSQL".
_BOUNDARY_COMPONENTS = [
    ("alb", ("aws_lb",), "Application Load Balancer", "https"),
    ("ecs", ("aws_ecs_service", "aws_ecs_cluster"), "ECS Fargate", "http"),
    ("rds", ("aws_db_instance", "aws_rds_cluster"), "RDS", "postgresql"),
    ("redis", ("aws_elasticache_replication_group",), "ElastiCache", "redis"),
]

# Data store type -> SSP component title substring for access-grant attachment.
_STORE_TITLE_MATCH = {
    "aws_secretsmanager_secret": "Secrets Manager",
    "aws_s3_bucket": "S3",
    "aws_ecr_repository": "Elastic Container Registry",
}


def build_boundary_protection(resources, listener_map, datastore_tls,  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
                              containers, iam_statements):
    """Build the boundary-protection dict for OSCAL SSP ingestion.

    Reuses the Phase A extractors; output is deterministic (callers should
    json.dump with sort_keys=True). Account/region appear only as <account>/
    <region> placeholders, never a real account id.
    """
    rds_tls = any(r.type == "aws_db_instance" and make_node_id(r) in datastore_tls
                  for r in resources)
    redis_tls = any(r.type == "aws_elasticache_replication_group"
                    and make_node_id(r) in datastore_tls for r in resources)

    # Resolve the ALB listener port/protocol/tls (forward listener wins).
    alb = next((r for r in resources if r.type == "aws_lb"), None)
    alb_meta = listener_map.get(make_node_id(alb)) if alb else None

    # Container ports keyed by role (nginx faces ALB on its first port).
    proxy = app = heimdall = None
    if containers:
        proxy, app, heimdall, _nodes = _pick_containers(containers)

    components = []
    for key, types, title_match, proto_name in _BOUNDARY_COMPONENTS:
        present = [r for r in resources if r.type in types]
        if not present:
            continue
        protocols = []
        if key == "alb" and alb_meta and alb_meta.get("port"):
            protocols.append(_proto(proto_name, alb_meta["port"],
                                    alb_meta.get("tls")))
        elif key == "ecs":
            # The ALB-facing container port (nginx :8080), else default 8080.
            port = (proxy[1]["ports"][0] if proxy and proxy[1]["ports"] else 8080)
            protocols.append(_proto(proto_name, port, None))
        elif key == "rds":
            protocols.append(_proto(proto_name, 5432, "TLS" if rds_tls else None))
        elif key == "redis":
            protocols.append(_proto(proto_name, 6379, "TLS" if redis_tls else None))
        if not protocols:
            continue
        entry = {"key": key, "title-match": title_match, "protocols": protocols}
        if key == "ecs":
            entry["access-grants"] = _access_grants(resources, iam_statements)
        components.append(entry)

    components.sort(key=lambda e: e["key"])
    return {"boundary-protection": {
        "generated-from": "terraform-state",
        "components": components,
    }}


def _proto(name, port, tls):
    """One OSCAL-friendly protocol record with a single port-range."""
    p = int(port) if str(port).isdigit() else port
    rec = {"name": name, "transport": "TCP", "start": p, "end": p}
    if tls:
        rec["tls"] = tls
    return rec


def _access_grants(resources, iam_statements):
    """IAM grants the ECS task role holds over each data store (sorted)."""
    grants = []
    for r in resources:
        match = _STORE_TITLE_MATCH.get(r.type)
        if not match:
            continue
        action, tmpl, _abbrev = iam_summary_for(r, iam_statements)
        if action:
            grants.append({"to-title-match": match, "action": action,
                           "arn": tmpl or "*"})
    grants.sort(key=lambda g: (g["to-title-match"], g["action"], g["arn"]))
    return grants


def generate_network_topology(resources, connections, datastore_tls=None):  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
    """Generate security group chain / network topology diagram."""
    # Collect security groups
    sgs = [r for r in resources if r.type in ("aws_security_group",
                                               "azurerm_network_security_group")]
    if not sgs:
        return ""

    lines = [
        "## Security Architecture",
        "",
        _MERMAID_FENCE,
        _GRAPH_LR,
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
    lines.append(_MERMAID_END)

    # Draw SG chain connections (only SG-to-SG, not resource-to-SG refs)
    sg_types = ("aws_security_group", "aws_security_group_rule",
                "azurerm_network_security_group")
    sg_connections = [c for c in connections
                      if c.src.type in sg_types and c.dst.type in sg_types
                      and c.label]  # Only labeled connections (port rules)

    # TLS-enforced ports get a TLS annotation on the SG edge (additive)
    tls_present = bool(datastore_tls)
    rds_tls = tls_present and any(
        r.type == "aws_db_instance" and make_node_id(r) in datastore_tls
        for r in resources)
    redis_tls = tls_present and any(
        r.type == "aws_elasticache_replication_group" and make_node_id(r) in datastore_tls
        for r in resources)

    seen = set()
    for c in sg_connections:
        src_id = make_node_id(c.src)
        dst_id = make_node_id(c.dst)
        key = (src_id, dst_id)
        if key not in seen:
            seen.add(key)
            label = c.label
            if (rds_tls and "5432" in str(c.port)) or (redis_tls and "6379" in str(c.port)):
                label = f"{label} TLS"
            lines.append(f"    {src_id} -->|{_esc(label)}| {dst_id}")

    # Collect secrets and IAM info
    secrets = [r for r in resources if r.type in ("aws_secretsmanager_secret",
                                                   "azurerm_key_vault_secret",
                                                   "azurerm_key_vault")]
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
        lines.append(_MERMAID_END)

    if monitors:
        lines.append("")
        lines.append('    subgraph Monitoring["Monitoring"]')
        for m in monitors[:6]:
            nid = make_node_id(m)
            label = make_label(m)
            lines.append(f'        {nid}["{_esc(label)}"]')
        lines.append(_MERMAID_END)

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
        _MERMAID_FENCE,
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
        "--output",
        help="Output markdown file path (e.g. docs/diagrams/ecs-architecture.md)",
    )
    parser.add_argument(
        "--boundary-json",
        help="Also write a machine-readable boundary-protection.json for OSCAL "
             "SSP ingestion (Phase B / #347)",
    )
    parser.add_argument(
        "--pattern", choices=["ecs", "ec2", "azure-vm"],
        help="Infrastructure pattern (auto-detected if omitted)",
    )
    parser.add_argument(
        "--github-step-summary", action="store_true",
        help="Write diagrams to GitHub Actions step summary",
    )
    parser.add_argument(
        "--allow-empty", action="store_true",
        help="Exit 0 (no-op) instead of failing when the state has no resources. "
             "Default is to fail loudly so a broken state capture can't silently "
             "leave a stale/empty diagram in place (#358).",
    )
    args = parser.parse_args()

    if not args.output and not args.boundary_json:
        parser.error("at least one of --output or --boundary-json is required")

    # Parse state
    state = parse_state(args.state_json)
    resources = extract_resources(state)

    if not resources:
        if args.allow_empty:
            print("Warning: no resources found in state JSON — "
                  "exiting 0 (--allow-empty)", file=sys.stderr)
            sys.exit(0)
        print("ERROR: no resources found in state JSON. Refusing to write an "
              "empty diagram (this usually means a broken/empty terraform show "
              "-json capture). Pass --allow-empty to override.", file=sys.stderr)
        sys.exit(1)

    # Detect pattern
    pattern = args.pattern or detect_pattern(resources)
    print(f"Pattern: {pattern}", file=sys.stderr)

    # Classify and detect connections
    classified = classify_resources(resources)
    connections = detect_connections(resources)

    # Enrichment passes (ports / protocols / TLS / ARN templates / IAM actions)
    listener_map = extract_listener_map(resources)
    datastore_tls = extract_datastore_tls(resources)
    containers = extract_task_containers(resources)
    iam_statements = extract_iam_statements(resources)

    total_resources = len(resources)
    total_connections = len(connections)

    print(f"Resources: {total_resources}", file=sys.stderr)
    print(f"Connections: {total_connections}", file=sys.stderr)
    for cat in CATEGORY_ORDER:
        count = len(classified.get(cat, []))
        if count:
            print(f"  {CATEGORY_LABELS.get(cat, cat)}: {count}", file=sys.stderr)

    # Generate diagrams — small, focused C4 "bites" plus an auditor table
    diagrams = [
        generate_system_context(resources, pattern),
        generate_dataplane_flow(resources, classified, pattern, listener_map,
                                containers, datastore_tls),
        generate_data_access(resources, iam_statements),
        generate_network_topology(resources, connections, datastore_tls),
        generate_observability(resources),
        generate_boundary_reference(resources, connections, listener_map,
                                    datastore_tls, iam_statements),
        generate_module_dependency(resources),
    ]

    # Assemble document
    doc = assemble_document(diagrams, pattern, total_resources, total_connections)

    # Write markdown output
    if args.output:
        os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
        with open(args.output, "w") as f:
            f.write(doc)
        print(f"Wrote {args.output}", file=sys.stderr)

    # Write machine-readable boundary-protection.json (Phase B / #347)
    if args.boundary_json:
        boundary = build_boundary_protection(resources, listener_map,
                                             datastore_tls, containers,
                                             iam_statements)
        os.makedirs(os.path.dirname(args.boundary_json) or ".", exist_ok=True)
        with open(args.boundary_json, "w") as f:
            json.dump(boundary, f, indent=2, sort_keys=True)
            f.write("\n")
        print(f"Wrote {args.boundary_json}", file=sys.stderr)

    # GitHub step summary
    if args.github_step_summary:
        write_step_summary(doc)
        print("Wrote GitHub step summary", file=sys.stderr)


if __name__ == "__main__":
    main()
