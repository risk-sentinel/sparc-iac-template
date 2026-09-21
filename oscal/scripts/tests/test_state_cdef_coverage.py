"""Unit tests for state_cdef_coverage.py (the #287 CDEF rebaseline analyzer)."""
from __future__ import annotations

import state_cdef_coverage as sc


def _managed(rtype, n=1):
    return {"mode": "managed", "type": rtype, "instances": [{}] * n}


def _data(rtype):
    return {"mode": "data", "type": rtype, "instances": [{}]}


def test_resource_service_specific_before_general():
    # cloudtrail must NOT fold into cloudwatch
    assert sc.resource_service("aws_cloudtrail") == "cloudtrail"
    assert sc.resource_service("aws_cloudwatch_log_group") == "cloudwatch"
    # EventBridge: both legacy cw_event and scheduler map to eventbridge
    assert sc.resource_service("aws_cloudwatch_event_rule") == "eventbridge"
    assert sc.resource_service("aws_scheduler_schedule") == "eventbridge"
    # ALB family folds to elb
    assert sc.resource_service("aws_lb_listener") == "elb"
    assert sc.resource_service("aws_db_instance") == "rds"
    assert sc.resource_service("aws_wafv2_web_acl") == "waf"
    assert sc.resource_service("aws_vpc") == "vpc"
    assert sc.resource_service("aws_subnet") == "vpc"
    # unmapped
    assert sc.resource_service("aws_totally_made_up") is None


def test_deployed_services_ignores_data_sources():
    state = {"resources": [
        _managed("aws_ecs_cluster"),
        _managed("aws_ecs_service"),
        _data("aws_caller_identity"),   # data source — must be skipped
        _data("aws_iam_policy_document"),
        _managed("aws_lb", 1),
    ]}
    svc, unmapped = sc.deployed_services([state])
    assert set(svc) == {"ecs", "elb"}
    assert svc["ecs"]["count"] == 2
    assert unmapped == {}


def test_deployed_services_reports_unmapped():
    state = {"resources": [_managed("aws_brandnew_widget", 3)]}
    svc, unmapped = sc.deployed_services([state])
    assert svc == {}
    assert unmapped == {"aws_brandnew_widget": 3}


def test_classify_adopt_keep_needs():
    svc = {
        "s3": {"types": {"aws_s3_bucket"}, "count": 1},        # AWS Labs -> ADOPT
        "vpc": {"types": {"aws_vpc"}, "count": 1},              # custom -> KEEP-CUSTOM
        "widget": {"types": {"aws_widget"}, "count": 1},       # neither -> NEEDS-CUSTOM
    }
    aws_labs = {"s3", "acm"}
    custom = {"vpc-networking": "x"}  # aliases to "vpc"
    rows, stale = sc.classify(svc, aws_labs, custom)
    verdicts = {s: v for s, v, *_ in rows}
    assert verdicts == {"s3": "ADOPT", "vpc": "KEEP-CUSTOM", "widget": "NEEDS-CUSTOM"}
    assert stale == []


def test_always_keep_not_flagged_stale():
    # nginx/pipeline hold custom CDEFs but never appear in state -> not STALE
    svc = {"ecs": {"types": {"aws_ecs_cluster"}, "count": 1}}
    aws_labs = {"ecs"}
    custom = {"nginx": "x", "pipeline": "x", "elasticache": "x"}
    _, stale = sc.classify(svc, aws_labs, custom)
    assert "nginx" not in stale and "pipeline" not in stale
    # elasticache IS a real AWS service we no longer deploy -> STALE
    assert stale == ["elasticache"]


def test_custom_alias_resolution():
    # a custom "alb" CDEF should satisfy a deployed "elb" service (alias)
    svc = {"elb": {"types": {"aws_lb"}, "count": 1}}
    rows, stale = sc.classify(svc, aws_labs=set(), custom={"alb": "x"})
    assert rows[0][1] == "KEEP-CUSTOM"
    assert stale == []
