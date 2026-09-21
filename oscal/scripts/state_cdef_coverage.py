#!/usr/bin/env python3
"""CDEF coverage analyzer — rebaseline OSCAL Component Definitions from live TF state.

Reads one or more Terraform state files (local path or ``s3://bucket/key``),
enumerates the AWS services actually DEPLOYED (``managed`` resources only, never
data sources), and cross-references them against:

  * **AWS Labs** published CDEFs (``awslabs/oscal-content-for-aws-services``) — the
    authoritative adopt set (``--aws-labs-manifest`` file of service names, or
    ``--aws-labs-cdef-dir`` of vendored ``<service>.oscal.json`` files), and
  * our **custom** CDEFs (``--custom-cdef-dir``) — what we already maintain.

Every deployed service is classified:

  ``ADOPT``         deployed + AWS Labs publishes a CDEF        -> vendor theirs
  ``KEEP-CUSTOM``   deployed + no AWS Labs CDEF + we have one   -> keep our overlay
  ``NEEDS-CUSTOM``  deployed + no AWS Labs CDEF + we have none  -> author a CDEF
  ``STALE-CUSTOM``  we maintain a CDEF but the service is NOT   -> drop / verify
                    deployed in any given state

Non-AWS components that legitimately have a CDEF but never appear in TF state
(the nginx sidecar, the CI/CD pipeline) are listed in ``ALWAYS_KEEP`` so they are
reported KEEP-CUSTOM rather than false-flagged STALE.

Since #597 the canonical example boundary is a SINGLE state — AWS Config was
consolidated into ``sparc/ecs`` and the ``sparc/config`` state retired, so a
coverage run that still passes it would report every Config service STALE-CUSTOM
against an empty state. ``--state`` stays repeatable for boundaries that legitimately
span states::

  state_cdef_coverage.py \
    --state s3://<tf-state-bucket>/sparc/ecs/terraform.tfstate \
    --aws-labs-cdef-dir AWS/CDEF/aws-labs \
    --custom-cdef-dir AWS/CDEF/ECS \
    --format table

``--fail-on`` (comma list of verdicts, e.g. ``NEEDS-CUSTOM,STALE-CUSTOM``) makes
the script exit non-zero when any deployed service lands in one of those buckets
— for use as a weekly CI drift check (#287).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

# Ordered resource-type -> service rules (specific before general). Service names
# match AWS Labs CDEF basenames (component-definitions/<service>.oscal.json).
RULES: list[tuple[str, str]] = [
    (r"^aws_acm_", "acm"),
    (r"^aws_cloudtrail", "cloudtrail"),
    (r"^aws_cloudwatch_event", "eventbridge"),   # EventBridge (legacy cw_event name)
    (r"^aws_scheduler_", "eventbridge"),          # EventBridge Scheduler
    (r"^aws_cloudwatch_", "cloudwatch"),
    (r"^aws_config_", "config"),
    (r"^aws_(lb|elb|alb)($|_)", "elb"),
    (r"^aws_ecr_", "ecr"),
    (r"^aws_ecs_", "ecs"),
    (r"^aws_elasticache_", "elasticache"),
    (r"^aws_guardduty_", "guardduty"),
    (r"^aws_iam_", "iam"),
    (r"^aws_kms_", "kms"),
    (r"^aws_lambda_", "lambda"),
    (r"^aws_(db_|rds_)", "rds"),
    (r"^aws_route53_", "route53"),
    (r"^aws_s3_", "s3"),
    (r"^aws_secretsmanager_", "secretsmanager"),
    (r"^aws_ses_", "ses"),
    (r"^aws_sns_", "sns"),
    (r"^aws_sqs_", "sqs"),
    (r"^aws_ssm_", "ssm"),
    (r"^aws_(wafv2_|waf_)", "waf"),
    (r"^aws_(vpc($|_)|subnet|route_table|route($|_)|internet_gateway|nat_|"
     r"network_|default_security_group|security_group|flow_log|egress_only)", "vpc"),
    (r"^aws_(autoscaling_|launch_template|launch_configuration)", "autoscaling"),
    (r"^aws_serverlessapplicationrepository_", "serverlessrepo"),
]

# custom CDEF basename -> analyzer service key, where the two differ.
CUSTOM_ALIAS: dict[str, str] = {
    "alb": "elb",
    "ecs-fargate": "ecs",
    "secrets": "secretsmanager",
    "vpc-networking": "vpc",
    "ses-email": "ses",
    "cis-rhel9-runner": "autoscaling",
}

# Components that legitimately hold a CDEF but never appear in TF state because
# they are not AWS resources (a container sidecar; the CI/CD pipeline). Reported
# KEEP-CUSTOM, never STALE.
ALWAYS_KEEP: set[str] = {"nginx", "pipeline"}


def resource_service(rtype: str) -> str | None:
    for pat, svc in RULES:
        if re.match(pat, rtype):
            return svc
    return None  # unmapped managed resource — reported separately


def load_state(ref: str) -> dict:
    """Load a tfstate from a local path or ``s3://`` URI."""
    if ref.startswith("s3://"):
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".tfstate")
        tmp.close()
        try:
            subprocess.run(["aws", "s3", "cp", ref, tmp.name],
                           check=True, capture_output=True)
            with open(tmp.name) as fh:
                return json.load(fh)
        finally:
            os.unlink(tmp.name)
    with open(ref) as fh:
        return json.load(fh)


def deployed_services(states: list[dict]) -> tuple[dict, dict]:
    """Return ({service: {"types": set, "count": int}}, {unmapped_type: count})."""
    svc: dict[str, dict] = {}
    unmapped: dict[str, int] = {}
    for st in states:
        for res in st.get("resources", []):
            if res.get("mode") != "managed":
                continue  # data sources are not "deployed"
            rtype = res.get("type", "")
            if not rtype.startswith("aws_"):
                continue
            n = len(res.get("instances", []))
            service = resource_service(rtype)
            if service is None:
                unmapped[rtype] = unmapped.get(rtype, 0) + n
                continue
            svc.setdefault(service, {"types": set(), "count": 0})
            svc[service]["types"].add(rtype)
            svc[service]["count"] += n
    return svc, unmapped


def _services_from_dir(path: str, custom: bool) -> dict[str, str]:
    """Map service-key -> file for a dir of CDEFs.

    custom dirs use ``component-definition-<svc>.json``; AWS Labs vendored dirs use
    ``<svc>.oscal.json``.
    """
    out: dict[str, str] = {}
    if not os.path.isdir(path):
        return out
    for fn in sorted(os.listdir(path)):
        if fn == "component-definition-template.json":
            continue
        if custom and fn.endswith(".json"):
            key = re.sub(r"\.json$", "", re.sub(r"^component-definition-?", "", fn))
        elif not custom and fn.endswith(".oscal.json"):
            key = re.sub(r"\.oscal\.json$", "", fn)
        else:
            continue
        out[key.lower()] = os.path.join(path, fn)
    return out


def load_aws_labs(manifest: str | None, cdef_dirs: list[str]) -> set[str]:
    services: set[str] = set()
    if manifest:
        with open(manifest) as fh:
            services |= {ln.strip().lower() for ln in fh if ln.strip()}
    for d in cdef_dirs:
        services |= set(_services_from_dir(d, custom=False))
    return services


def load_custom(cdef_dirs: list[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    for d in cdef_dirs:
        out.update(_services_from_dir(d, custom=True))
    return out


def classify(svc: dict, aws_labs: set[str], custom: dict) -> tuple[list, list]:
    custom_keys = {CUSTOM_ALIAS.get(k, k) for k in custom} | ALWAYS_KEEP
    rows = []
    for service in sorted(svc):
        if service in aws_labs:
            verdict, source = "ADOPT", "aws-labs"
        elif service in custom_keys:
            verdict, source = "KEEP-CUSTOM", "custom"
        else:
            verdict, source = "NEEDS-CUSTOM", "-"
        rows.append((service, verdict, svc[service]["count"], source,
                     ",".join(sorted(svc[service]["types"]))))
    deployed = set(svc)
    stale = sorted(
        ({CUSTOM_ALIAS.get(k, k) for k in custom} - deployed) - ALWAYS_KEEP
    )
    return rows, stale


def main() -> int:
    ap = argparse.ArgumentParser(description="Rebaseline CDEFs from TF state")
    ap.add_argument("--state", action="append", required=True,
                    help="tfstate (local path or s3://...); repeatable — pass ALL "
                         "boundary states. sparc/ecs alone covers the AWS "
                         "boundary since #597 retired sparc/config.")
    ap.add_argument("--aws-labs-manifest",
                    help="file of AWS Labs CDEF service names, one per line")
    ap.add_argument("--aws-labs-cdef-dir", action="append", default=[],
                    help="dir of vendored AWS Labs <svc>.oscal.json; repeatable")
    ap.add_argument("--custom-cdef-dir", action="append", default=[],
                    help="dir of our custom CDEFs; repeatable")
    ap.add_argument("--format", choices=["table", "json"], default="table")
    ap.add_argument("--fail-on", default="",
                    help="comma list of verdicts that force exit 1 "
                         "(e.g. NEEDS-CUSTOM,STALE-CUSTOM) — for CI drift checks")
    args = ap.parse_args()

    if not args.aws_labs_manifest and not args.aws_labs_cdef_dir:
        ap.error("provide --aws-labs-manifest and/or --aws-labs-cdef-dir")

    states = [load_state(s) for s in args.state]
    aws_labs = load_aws_labs(args.aws_labs_manifest, args.aws_labs_cdef_dir)
    custom = load_custom(args.custom_cdef_dir)
    svc, unmapped = deployed_services(states)
    rows, stale = classify(svc, aws_labs, custom)

    fail_on = {v.strip().upper() for v in args.fail_on.split(",") if v.strip()}
    verdicts = {v for _, v, *_ in rows}
    if stale:
        verdicts.add("STALE-CUSTOM")
    breached = fail_on & verdicts

    if args.format == "json":
        print(json.dumps({
            "deployed": {s: {"verdict": v, "count": c, "source": src,
                             "types": t.split(",") if t else []}
                         for s, v, c, src, t in rows},
            "stale_custom": stale,
            "unmapped_types": unmapped,
        }, indent=2))
    else:
        print(f"\n{'SERVICE':<18}{'VERDICT':<14}{'#':>4}  {'SOURCE':<10} RESOURCE TYPES")
        print("-" * 100)
        for s, v, c, src, types in rows:
            print(f"{s:<18}{v:<14}{c:>4}  {src:<10} {types[:58]}")
        counts: dict[str, int] = {}
        for _, v, *_ in rows:
            counts[v] = counts.get(v, 0) + 1
        print("-" * 100)
        print("summary:", ", ".join(f"{k}={counts[k]}" for k in sorted(counts)),
              f"| deployed-services={len(rows)}")
        if stale:
            print("\nSTALE-CUSTOM (CDEF exists, NOT deployed -> drop/verify): "
                  + ", ".join(stale))
        if unmapped:
            print("\nUNMAPPED managed types (add a RULE if a real service): "
                  + ", ".join(sorted(unmapped)))

    if breached:
        print(f"\nFAIL: verdict(s) present that --fail-on flags: "
              f"{', '.join(sorted(breached))}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
