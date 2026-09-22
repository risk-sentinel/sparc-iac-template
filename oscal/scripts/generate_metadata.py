#!/usr/bin/env python3
"""
Generate metadata.json for S3 artifact archive.

Captures run context (commit, timestamp, event) and compliance metrics
(pass/fail counts per pattern, SSP coverage) for trend tracking.

Usage:
    python3 oscal/scripts/generate_metadata.py \
        --pattern ecs \
        --checkov-results checkov-results/checkov-ecs-*.json \
        --trend-json checkov-results/checkov-trend-ecs.json \
        --ssp oscal/ssp/ecs-ssp.json \
        --output metadata.json
"""

import argparse
import json
import os
from datetime import datetime, timezone


def load_checkov_summary(path):
    """Extract pass/fail from Checkov JSON results."""
    if not path or not os.path.exists(path):
        return {"passed": 0, "failed": 0}
    with open(path) as f:
        data = json.load(f)
    if isinstance(data, list):
        data = data[0] if data else {}
    summary = data.get("summary", {})
    return {
        "passed": summary.get("passed", 0),
        "failed": summary.get("failed", 0),
    }


def load_trend_summary(path):
    """Extract trend metrics from checkov_diff.py output."""
    if not path or not os.path.exists(path):
        return {}
    with open(path) as f:
        return json.load(f).get("summary", {})


def count_ssp_controls(path):
    """Count implemented controls in an SSP."""
    if not path or not os.path.exists(path):
        return {"covered": 0, "total": 0}
    with open(path) as f:
        ssp = json.load(f)
    results = ssp.get("system-security-plan", {}).get("control-implementation", {})
    reqs = results.get("implemented-requirements", [])
    return {"covered": len(reqs), "total": 370}


def main():
    parser = argparse.ArgumentParser(description="Generate artifact metadata.json")
    parser.add_argument("--pattern", required=True)
    parser.add_argument("--checkov-results", default="")
    parser.add_argument("--trend-json", default="")
    parser.add_argument("--ssp", default="")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    checkov = load_checkov_summary(args.checkov_results)
    trend = load_trend_summary(args.trend_json)
    ssp = count_ssp_controls(args.ssp)

    total = checkov["passed"] + checkov["failed"]
    pass_rate = (checkov["passed"] / total * 100) if total > 0 else 0

    metadata = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "commit": os.environ.get("GITHUB_SHA", "unknown")[:7],
        "branch": os.environ.get("GITHUB_REF_NAME", "unknown"),
        "event": os.environ.get("GITHUB_EVENT_NAME", "unknown"),
        "run_id": os.environ.get("GITHUB_RUN_ID", "unknown"),
        "run_url": f"{os.environ.get('GITHUB_SERVER_URL', '')}/{os.environ.get('GITHUB_REPOSITORY', '')}/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}",
        "pattern": args.pattern,
        "checkov": {
            "passed": checkov["passed"],
            "failed": checkov["failed"],
            "pass_rate": round(pass_rate, 1),
        },
        "disposition": trend,
        "ssp": {
            "controls_covered": ssp["covered"],
            "controls_total": ssp["total"],
            "coverage_pct": round(ssp["covered"] / ssp["total"] * 100, 1) if ssp["total"] > 0 else 0,
        },
    }

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(metadata, f, indent=2)

    print(f"Metadata written to {args.output}")
    print(f"  Pattern: {args.pattern}")
    print(f"  Checkov: {checkov['passed']}/{total} ({pass_rate:.1f}%)")
    print(f"  SSP coverage: {ssp['covered']}/{ssp['total']}")


if __name__ == "__main__":
    main()
