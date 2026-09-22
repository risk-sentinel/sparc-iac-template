"""Tests for the boundary-protection merge in assemble_ssp.py (#347).

Covers apply_boundary_protection: native OSCAL protocols[]/port-ranges[] +
custom-ns props[] attached to title-matched components, non-matching
components left untouched, stable protocol UUIDs, and the empty/no-op path.
"""

from __future__ import annotations

import assemble_ssp as asp


def _components():
    return [
        {"uuid": "u-alb", "type": "service", "title": "AWS Application Load Balancer",
         "description": "d", "status": {"state": "operational"}},
        {"uuid": "u-rds", "type": "service", "title": "AWS RDS PostgreSQL",
         "description": "d", "status": {"state": "operational"}},
        {"uuid": "u-ecs", "type": "service", "title": "AWS ECS Fargate",
         "description": "d", "status": {"state": "operational"}},
        {"uuid": "u-kms", "type": "service", "title": "AWS KMS Customer-Managed Keys",
         "description": "d", "status": {"state": "operational"}},
    ]


def _boundary():
    return {
        "components": [
            {"key": "alb", "title-match": "Application Load Balancer",
             "protocols": [{"name": "https", "transport": "TCP", "start": 443,
                            "end": 443, "tls": "TLS1.2+"}]},
            {"key": "rds", "title-match": "RDS",
             "protocols": [{"name": "postgresql", "transport": "TCP", "start": 5432,
                            "end": 5432, "tls": "TLS"}]},
            {"key": "ecs", "title-match": "ECS Fargate",
             "protocols": [{"name": "http", "transport": "TCP", "start": 8080, "end": 8080}],
             "access-grants": [{"to-title-match": "Secrets Manager",
                               "action": "GetSecretValue",
                               "arn": "arn:aws:secretsmanager:<region>:<account>:secret:example-*"}]},
        ]
    }


def test_protocols_attached_to_matching_component(org_config):
    comps = asp.apply_boundary_protection(_components(), _boundary(), org_config)
    rds = next(c for c in comps if c["uuid"] == "u-rds")
    pr = rds["protocols"][0]
    assert pr["name"] == "postgresql"
    assert pr["port-ranges"][0] == {"start": 5432, "end": 5432, "transport": "TCP"}
    assert "uuid" in pr


def test_tls_and_dataaccess_props(org_config):
    comps = asp.apply_boundary_protection(_components(), _boundary(), org_config)
    rds = next(c for c in comps if c["uuid"] == "u-rds")
    assert any(p["name"] == "transit-encryption" and "TLS" in p["value"]
               for p in rds["props"])
    ecs = next(c for c in comps if c["uuid"] == "u-ecs")
    da = [p for p in ecs["props"] if p["name"] == "data-access"]
    assert da and "GetSecretValue" in da[0]["value"]
    assert da[0]["ns"] == asp.BOUNDARY_NS


def test_non_matching_component_untouched(org_config):
    comps = asp.apply_boundary_protection(_components(), _boundary(), org_config)
    kms = next(c for c in comps if c["uuid"] == "u-kms")
    assert "protocols" not in kms and "props" not in kms


def test_no_account_leak(org_config):
    import json
    comps = asp.apply_boundary_protection(_components(), _boundary(), org_config)
    assert "123456789012" not in json.dumps(comps)


def test_protocol_uuid_is_stable(org_config):
    a = asp.apply_boundary_protection(_components(), _boundary(), org_config)
    b = asp.apply_boundary_protection(_components(), _boundary(), org_config)
    ua = next(c for c in a if c["uuid"] == "u-alb")["protocols"][0]["uuid"]
    ub = next(c for c in b if c["uuid"] == "u-alb")["protocols"][0]["uuid"]
    assert ua == ub


def test_empty_boundary_is_noop(org_config):
    comps = asp.apply_boundary_protection(_components(), {}, org_config)
    assert all("protocols" not in c and "props" not in c for c in comps)


def test_load_boundary_protection_missing_file_returns_empty():
    assert asp.load_boundary_protection("") == {}
    assert asp.load_boundary_protection("/nonexistent/boundary.json") == {}
