"""Tests for the enrichment passes added to generate_diagrams.py (#286).

Covers ARN templating, IAM statement parsing/matching, TLS derivation,
container-definition parsing, group collapsing, the legacy-compatible
Connection namedtuple, and an end-to-end render of the enriched document.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import generate_diagrams as gd

_SCRIPT = Path(gd.__file__)
_FIXTURES = Path(__file__).resolve().parent / "fixtures"


def _run(*args):
    """Run generate_diagrams.py as a subprocess; return CompletedProcess."""
    return subprocess.run(
        [sys.executable, str(_SCRIPT), *args],
        capture_output=True, text=True,
    )


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


def _resources(load_fixture):
    state = load_fixture("tfstate-ecs-minimal")
    return gd.extract_resources(state)


def _find(resources, rtype, name=None):
    for r in resources:
        if r.type == rtype and (name is None or r.name == name):
            return r
    raise AssertionError(f"resource {rtype}/{name} not found")


# ---------------------------------------------------------------------------
# ARN templating
# ---------------------------------------------------------------------------


def test_template_arn_strips_account_and_region():
    arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:example-db-EXAMPLE0001"
    out = gd.template_arn(arn)
    assert out == "arn:aws:secretsmanager:<region>:<account>:secret:example-db-EXAMPLE0001"
    assert "123456789012" not in out
    assert "us-east-1" not in out


def test_template_arn_leaves_s3_untouched():
    # S3 ARNs have no region/account segment.
    assert gd.template_arn("arn:aws:s3:::example-uploads") == "arn:aws:s3:::example-uploads"


def test_template_arn_does_not_clobber_12_digit_name():
    # A 12-digit run inside a resource name (not colon-anchored) must survive.
    arn = "arn:aws:s3:::bucket-123456789012-logs"
    assert gd.template_arn(arn) == "arn:aws:s3:::bucket-123456789012-logs"


def test_template_arn_passthrough_non_arn():
    assert gd.template_arn("not-an-arn") == "not-an-arn"
    assert gd.template_arn(None) is None


def test_abbreviate_arn():
    assert gd.abbreviate_arn(
        "arn:aws:secretsmanager:us-east-1:123456789012:secret:example-*"
    ) == "secret:example-*"
    assert gd.abbreviate_arn("arn:aws:s3:::example-uploads") == "example-uploads"


# ---------------------------------------------------------------------------
# IAM statement parsing & matching
# ---------------------------------------------------------------------------


def test_extract_iam_statements(load_fixture):
    stmts = gd.extract_iam_statements(_resources(load_fixture))
    assert len(stmts) == 1
    st = stmts[0]
    assert st["actions"] == ["secretsmanager:GetSecretValue"]
    assert st["resources"] == [
        "arn:aws:secretsmanager:<region>:<account>:secret:example-*"
    ]


def _stmt(policy):
    r = gd.Resource(module="iam", type="aws_iam_role_policy", name="p",
                    values={"policy": json.dumps(policy)}, provider="aws")
    return gd.extract_iam_statements([r])


def test_extract_iam_action_str_and_list_normalized():
    one = _stmt({"Statement": [{"Effect": "Allow", "Action": "s3:GetObject", "Resource": "*"}]})
    many = _stmt({"Statement": [{"Effect": "Allow",
                                 "Action": ["s3:GetObject", "s3:PutObject"], "Resource": "*"}]})
    assert one[0]["actions"] == ["s3:GetObject"]
    assert many[0]["actions"] == ["s3:GetObject", "s3:PutObject"]


def test_extract_iam_single_dict_statement_wrapped():
    out = _stmt({"Statement": {"Effect": "Allow", "Action": "s3:GetObject", "Resource": "*"}})
    assert len(out) == 1


def test_extract_iam_skips_deny_and_notaction():
    deny = _stmt({"Statement": [{"Effect": "Deny", "Action": "s3:*", "Resource": "*"}]})
    notaction = _stmt({"Statement": [{"Effect": "Allow", "NotAction": "s3:*", "Resource": "*"}]})
    assert deny == []
    assert notaction == []


def test_iam_summary_for_matches_wildcard_pattern(load_fixture):
    resources = _resources(load_fixture)
    secret = _find(resources, "aws_secretsmanager_secret")
    stmts = gd.extract_iam_statements(resources)
    action, tmpl, abbrev = gd.iam_summary_for(secret, stmts)
    assert action == "GetSecretValue"
    assert tmpl == "arn:aws:secretsmanager:<region>:<account>:secret:example-*"
    assert abbrev == "secret:example-db-EXAMPLE0001"


def test_iam_summary_for_prefers_service_over_wildcard_xray():
    # An xray:* grant on Resource "*" matches every ARN but must NOT be
    # attributed to a secret; the secretsmanager grant wins.
    secret = gd.Resource(
        "rds", "aws_secretsmanager_secret", "db",
        {"arn": "arn:aws:secretsmanager:us-east-1:123456789012:secret:example/db-EXAMPLE0006"},
        "aws")
    stmts = [
        {"actions": ["xray:PutTraceSegments", "xray:PutTelemetryRecords"],
         "resources": ["*"], "raw_resources": ["*"]},
        {"actions": ["secretsmanager:GetSecretValue"],
         "resources": ["arn:aws:secretsmanager:<region>:<account>:secret:example/db-EXAMPLE0006"],
         "raw_resources": ["arn:aws:secretsmanager:us-east-1:123456789012:secret:example/db-EXAMPLE0006"]},
    ]
    action, tmpl, _ = gd.iam_summary_for(secret, stmts)
    assert action == "GetSecretValue"
    assert "secretsmanager" in tmpl


def test_iam_summary_for_only_irrelevant_wildcard_returns_none():
    # If the ONLY match is an unrelated-service wildcard, report no grant
    # rather than a misleading one.
    secret = gd.Resource(
        "rds", "aws_secretsmanager_secret", "db",
        {"arn": "arn:aws:secretsmanager:us-east-1:123456789012:secret:example/db-X"}, "aws")
    stmts = [{"actions": ["xray:PutTraceSegments"], "resources": ["*"], "raw_resources": ["*"]}]
    assert gd.iam_summary_for(secret, stmts) == (None, None, None)


def test_iam_summary_for_prefers_specific_arn_over_wildcard():
    secret = gd.Resource(
        "rds", "aws_secretsmanager_secret", "db",
        {"arn": "arn:aws:secretsmanager:us-east-1:123456789012:secret:example/admin-EXAMPLE0004"}, "aws")
    stmts = [
        {"actions": ["secretsmanager:GetSecretValue"],
         "resources": ["arn:aws:secretsmanager:<region>:<account>:secret:sparc-*"],
         "raw_resources": ["arn:aws:secretsmanager:us-east-1:123456789012:secret:sparc-*"]},
        {"actions": ["secretsmanager:UpdateSecretVersionStage", "secretsmanager:PutSecretValue"],
         "resources": ["arn:aws:secretsmanager:<region>:<account>:secret:example/admin-EXAMPLE0004"],
         "raw_resources": ["arn:aws:secretsmanager:us-east-1:123456789012:secret:example/admin-EXAMPLE0004"]},
    ]
    action, tmpl, _ = gd.iam_summary_for(secret, stmts)
    # exact-ARN statement (specificity 2) beats the sparc-* wildcard (specificity 1)
    assert action == "UpdateSecretVersionStage +1"
    assert tmpl.endswith("admin-vilXwa")


def test_iam_summary_for_no_match_returns_none():
    target = gd.Resource(module="s3", type="aws_s3_bucket", name="other",
                         values={"arn": "arn:aws:s3:::unrelated"}, provider="aws")
    stmts = [{"actions": ["s3:GetObject"], "resources": ["arn:aws:s3:::sparc-*"],
              "raw_resources": ["arn:aws:s3:::sparc-*"]}]
    assert gd.iam_summary_for(target, stmts) == (None, None, None)


def test_arn_glob_match_star_matches_anything():
    assert gd._arn_glob_match("*", "arn:aws:s3:::anything")
    assert gd._arn_glob_match("arn:aws:s3:::sparc-*", "arn:aws:s3:::sparc-uploads")
    assert not gd._arn_glob_match("arn:aws:s3:::sparc-*", "arn:aws:s3:::other")


def test_shorten_actions():
    assert gd._shorten_actions(["secretsmanager:GetSecretValue"]) == "GetSecretValue"
    assert gd._shorten_actions(["s3:GetObject", "s3:PutObject", "s3:ListBucket"]) == "GetObject +2"
    assert gd._shorten_actions([]) is None


# ---------------------------------------------------------------------------
# TLS derivation
# ---------------------------------------------------------------------------


def test_extract_datastore_tls(load_fixture):
    resources = _resources(load_fixture)
    tls = gd.extract_datastore_tls(resources)
    rds = _find(resources, "aws_db_instance")
    redis = _find(resources, "aws_elasticache_replication_group")
    assert tls.get(gd.make_node_id(rds)) == "TLS"
    assert tls.get(gd.make_node_id(redis)) == "TLS"


def test_extract_datastore_tls_force_ssl_off():
    r_db = gd.Resource("rds", "aws_db_instance", "main",
                       {"id": "db", "parameter_group_name": "pg"}, "aws")
    r_pg = gd.Resource("rds", "aws_db_parameter_group", "main",
                       {"name": "pg", "parameter": [{"name": "rds.force_ssl", "value": "0"}]}, "aws")
    assert gd.extract_datastore_tls([r_db, r_pg]) == {}


def test_tls_from_ssl_policy():
    assert gd._tls_from_ssl_policy("ELBSecurityPolicy-TLS13-1-2-2021-06") == "TLS1.2+"
    assert gd._tls_from_ssl_policy("ELBSecurityPolicy-2016-08") == "TLS"
    assert gd._tls_from_ssl_policy("") is None
    assert gd._tls_from_ssl_policy(None) is None


def test_extract_listener_map_prefers_forward(load_fixture):
    resources = _resources(load_fixture)
    lmap = gd.extract_listener_map(resources)
    alb = _find(resources, "aws_lb")
    meta = lmap[gd.make_node_id(alb)]
    assert meta["port"] == 443
    assert meta["protocol"] == "HTTPS"
    assert meta["tls"] == "TLS1.2+"
    assert meta["is_forward"] is True


# ---------------------------------------------------------------------------
# Container-definition parsing
# ---------------------------------------------------------------------------


def test_extract_task_containers(load_fixture):
    containers = gd.extract_task_containers(_resources(load_fixture))
    names = {c["name"]: c for c in containers}
    assert "example-nginx" in names
    assert names["example-nginx"]["ports"] == [8080]
    assert names["example"]["ports"] == [3000]


def test_extract_task_containers_bad_json_falls_back():
    r = gd.Resource("ecs", "aws_ecs_task_definition", "main",
                    {"container_definitions": "{not valid json"}, "aws")
    assert gd.extract_task_containers([r]) == []


# ---------------------------------------------------------------------------
# SG flows & collapse
# ---------------------------------------------------------------------------


def test_extract_sg_flows(load_fixture):
    flows = gd.extract_sg_flows(_resources(load_fixture))
    # ecs ingress 8080 from alb; rds 5432 from ecs; redis 6379 from ecs
    assert flows[("sg-alb", "sg-ecs")]["port"] == "8080"
    assert flows[("sg-ecs", "sg-rds")]["port"] == "5432"
    assert flows[("sg-ecs", "sg-redis")]["port"] == "6379"


def test_collapse_group_collapses_when_numerous():
    rs = [gd.Resource("m", "aws_cloudwatch_metric_alarm", f"a{i}",
                      {"id": f"al-{i}", "alarm_name": f"alarm-{i}"}, "aws")
          for i in range(5)]
    nodes = gd.collapse_group(rs, "CloudWatch alarms")
    assert len(nodes) == 1
    assert nodes[0][1] == "CloudWatch alarms (5)"


def test_collapse_group_individual_when_few():
    rs = [gd.Resource("m", "aws_sns_topic", "t1", {"id": "s1", "name": "t1"}, "aws")]
    nodes = gd.collapse_group(rs, "SNS Topics")
    assert len(nodes) == 1
    assert nodes[0][1] != "SNS Topics (1)"


# ---------------------------------------------------------------------------
# Backward compatibility
# ---------------------------------------------------------------------------


def test_connection_legacy_positional_still_works():
    src = gd.Resource("m", "aws_security_group", "a", {"id": "sg-a"}, "aws")
    dst = gd.Resource("m", "aws_security_group", "b", {"id": "sg-b"}, "aws")
    c = gd.Connection(src, dst, ":443", "-->")
    assert c.port is None and c.iam_action is None and c.tls is None


# ---------------------------------------------------------------------------
# Edge-label helper
# ---------------------------------------------------------------------------


def test_edge_label_variants():
    assert gd._edge_label(protocol="HTTPS", port=443, tls="TLS1.2+") == "HTTPS:443 TLS1.2+"
    assert gd._edge_label(port=8080) == ":8080"
    assert gd._edge_label(action="GetSecretValue", arn_abbrev="secret:example-*") == \
        "GetSecretValue<br/>secret:example-*"
    assert gd._edge_label(fallback="HTTPS") == "HTTPS"


# ---------------------------------------------------------------------------
# End-to-end document render
# ---------------------------------------------------------------------------


def _render(load_fixture):
    resources = _resources(load_fixture)
    classified = gd.classify_resources(resources)
    connections = gd.detect_connections(resources)
    listener_map = gd.extract_listener_map(resources)
    datastore_tls = gd.extract_datastore_tls(resources)
    containers = gd.extract_task_containers(resources)
    iam = gd.extract_iam_statements(resources)
    diagrams = [
        gd.generate_system_context(resources, "ecs"),
        gd.generate_dataplane_flow(resources, classified, "ecs", listener_map,
                                   containers, datastore_tls),
        gd.generate_data_access(resources, iam),
        gd.generate_network_topology(resources, connections, datastore_tls),
        gd.generate_observability(resources),
        gd.generate_boundary_reference(resources, connections, listener_map,
                                       datastore_tls, iam),
        gd.generate_module_dependency(resources),
    ]
    return gd.assemble_document(diagrams, "ecs", len(resources), len(connections))


def test_end_to_end_contains_enrichment(load_fixture):
    doc = _render(load_fixture)
    assert "## Data-Plane Flow (C4 Level 2)" in doc
    assert "## Data & Secrets Access" in doc
    assert "## Boundary Reference (FedRAMP SC-7)" in doc
    assert "## Observability" in doc
    assert "HTTPS:443 TLS1.2+" in doc
    assert "PostgreSQL:5432 TLS" in doc
    assert "Redis:6379 TLS" in doc
    assert "GetSecretValue" in doc
    assert "<account>" in doc and "<region>" in doc
    assert "CloudWatch (5 alarms)" in doc


def test_end_to_end_never_leaks_account_number(load_fixture):
    doc = _render(load_fixture)
    assert "123456789012" not in doc


def test_boundary_reference_is_deterministic(load_fixture):
    resources = _resources(load_fixture)
    connections = gd.detect_connections(resources)
    lmap = gd.extract_listener_map(resources)
    tls = gd.extract_datastore_tls(resources)
    iam = gd.extract_iam_statements(resources)
    a = gd.generate_boundary_reference(resources, connections, lmap, tls, iam)
    b = gd.generate_boundary_reference(resources, connections, lmap, tls, iam)
    assert a == b
    assert a.startswith("## Boundary Reference (FedRAMP SC-7)")


# ---------------------------------------------------------------------------
# build_boundary_protection (Phase B / #347)
# ---------------------------------------------------------------------------


def _boundary(load_fixture):
    resources = _resources(load_fixture)
    return gd.build_boundary_protection(
        resources,
        gd.extract_listener_map(resources),
        gd.extract_datastore_tls(resources),
        gd.extract_task_containers(resources),
        gd.extract_iam_statements(resources),
    )


def _comp(boundary, key):
    for c in boundary["boundary-protection"]["components"]:
        if c["key"] == key:
            return c
    return None


def test_build_boundary_protection_protocols(load_fixture):
    b = _boundary(load_fixture)
    alb = _comp(b, "alb")
    assert alb["title-match"] == "Application Load Balancer"
    assert alb["protocols"][0] == {"name": "https", "transport": "TCP",
                                   "start": 443, "end": 443, "tls": "TLS1.2+"}
    assert _comp(b, "ecs")["protocols"][0]["start"] == 8080
    rds = _comp(b, "rds")["protocols"][0]
    assert rds["start"] == 5432 and rds["tls"] == "TLS"
    assert _comp(b, "redis")["protocols"][0]["start"] == 6379


def test_build_boundary_protection_access_grants(load_fixture):
    grants = _comp(_boundary(load_fixture), "ecs")["access-grants"]
    sm = [g for g in grants if g["to-title-match"] == "Secrets Manager"]
    assert sm and sm[0]["action"] == "GetSecretValue"
    assert sm[0]["arn"] == "arn:aws:secretsmanager:<region>:<account>:secret:example-*"


def test_build_boundary_protection_no_account_leak(load_fixture):
    assert "123456789012" not in json.dumps(_boundary(load_fixture))


def test_build_boundary_protection_deterministic(load_fixture):
    a = json.dumps(_boundary(load_fixture), sort_keys=True)
    b = json.dumps(_boundary(load_fixture), sort_keys=True)
    assert a == b


def test_build_boundary_protection_omits_absent_components():
    # No RDS / Redis / ALB in this resource set -> those keys absent.
    r = gd.Resource("ecs", "aws_ecs_service", "main", {"id": "svc"}, "aws")
    b = gd.build_boundary_protection([r], {}, {}, [], [])
    keys = {c["key"] for c in b["boundary-protection"]["components"]}
    assert keys == {"ecs"}


# ---------------------------------------------------------------------------
# Fail-loud on empty / invalid state (#358)
# ---------------------------------------------------------------------------


def test_empty_state_exits_nonzero(tmp_path):
    out = tmp_path / "o.md"
    r = _run("--state-json", str(_FIXTURES / "tfstate-empty.json"), "--output", str(out))
    assert r.returncode != 0
    assert "no resources found" in r.stderr.lower()
    assert not out.exists()  # refused to write an empty diagram


def test_empty_state_allow_empty_exits_zero(tmp_path):
    out = tmp_path / "o.md"
    r = _run("--state-json", str(_FIXTURES / "tfstate-empty.json"),
             "--output", str(out), "--allow-empty")
    assert r.returncode == 0


def test_invalid_json_exits_nonzero(tmp_path):
    bad = tmp_path / "bad.json"
    bad.write_text("Warning: deprecated parameter\n{ not json")
    r = _run("--state-json", str(bad), "--output", str(tmp_path / "o.md"))
    assert r.returncode != 0
    assert "not valid json" in r.stderr.lower()


def test_empty_file_exits_nonzero(tmp_path):
    empty = tmp_path / "empty.json"
    empty.write_text("")
    r = _run("--state-json", str(empty), "--output", str(tmp_path / "o.md"))
    assert r.returncode != 0
    assert "empty" in r.stderr.lower()


def test_valid_state_still_succeeds(tmp_path):
    out = tmp_path / "o.md"
    r = _run("--state-json", str(_FIXTURES / "tfstate-ecs-minimal.json"), "--output", str(out))
    assert r.returncode == 0, r.stderr
    assert out.exists()
