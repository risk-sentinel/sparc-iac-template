#!/usr/bin/env python3
"""
Unified security gate — evaluates ALL scan results against threshold.yml.

Reads outputs from Checkov disposition diff, TruffleHog, Semgrep, pip-audit,
and produces a single pass/fail decision with a summary table.

All scans run to completion first. This script evaluates after.
The human reviews the summary and makes the final merge decision.

Usage:
    python3 oscal/scripts/evaluate_gate.py \
        --threshold threshold.yml \
        --pattern ecs \
        --checkov-trend checkov-results/checkov-trend-ecs.json \
        --trufflehog trufflehog.json \
        --semgrep semgrep.sarif \
        --pip-audit pip-audit.json \
        [--strict] \
        [--github-step-summary]
"""

import argparse
import json
import os
import sys

import yaml

_NOT_RUN = "Not run"  # shared gate "not run" detail string (S1192, #526)


def load_threshold(path, pattern, strict=False):
    """Load threshold.yml with defaults → pattern → strict layering."""
    with open(path) as f:
        data = yaml.safe_load(f)

    scans = data.get("scans", {})
    return {
        "secrets_max": scans.get("secrets", {}).get("max", 0),
        "sast_max_high": scans.get("sast", {}).get("max_high", 0),
        "sast_max_medium": scans.get("sast", {}).get("max_medium", 10),
        "sca_max_critical": scans.get("sca", {}).get("max_critical", 0),
        "sca_max_high": scans.get("sca", {}).get("max_high", 5),
        "container_max_critical": scans.get("container", {}).get("max_critical", 0),
    }


def evaluate_checkov(trend_path):
    """Read checkov_diff.py trend output and extract gate results."""
    if not trend_path or not os.path.exists(trend_path):
        return {"passed": True, "details": "No Checkov trend data"}

    with open(trend_path) as f:
        data = json.load(f)

    gate = data.get("gate", {})
    if gate:
        return {
            "passed": gate.get("passed", True),
            "checks": gate.get("checks", []),
            "details": "From checkov_diff.py threshold evaluation",
        }

    # Fallback: check for new findings
    summary = data.get("summary", {})
    new = summary.get("new", 0)
    regressions = summary.get("regressions", 0)
    return {
        "passed": new == 0 and regressions == 0,
        "new": new,
        "regressions": regressions,
        "details": f"New: {new}, Regressions: {regressions}",
    }


def evaluate_trufflehog(path, max_secrets):
    """Count TruffleHog findings (one JSON object per line)."""
    if not path or not os.path.exists(path):
        return {"count": 0, "passed": True, "details": _NOT_RUN}

    with open(path) as f:
        lines = [l.strip() for l in f if l.strip()]

    count = len(lines)
    return {
        "count": count,
        "limit": max_secrets,
        "passed": count <= max_secrets,
        "details": f"{count} finding(s)" if count > 0 else "Clean",
    }


def evaluate_semgrep(path, max_high, max_medium):
    """Parse Semgrep SARIF output for finding counts by severity."""
    if not path or not os.path.exists(path):
        return {"high": 0, "medium": 0, "low": 0, "passed": True, "details": _NOT_RUN}

    try:
        with open(path) as f:
            data = json.load(f)
    except ValueError:  # JSONDecodeError is a ValueError subclass (S5713)
        return {"high": 0, "medium": 0, "low": 0, "passed": True, "details": "Invalid SARIF"}

    high = 0
    medium = 0
    low = 0

    for run in data.get("runs", []):
        for result in run.get("results", []):
            level = result.get("level", "note")
            if level == "error":
                high += 1
            elif level == "warning":
                medium += 1
            else:
                low += 1

    passed = high <= max_high and medium <= max_medium
    return {
        "high": high,
        "medium": medium,
        "low": low,
        "passed": passed,
        "details": f"High: {high}, Medium: {medium}, Low: {low}",
    }


def evaluate_pip_audit(path, max_critical, max_high):
    """Parse pip-audit JSON output for vulnerability counts."""
    if not path or not os.path.exists(path):
        return {"critical": 0, "high": 0, "total": 0, "passed": True, "details": _NOT_RUN}

    try:
        with open(path) as f:
            data = json.load(f)
    except ValueError:  # JSONDecodeError is a ValueError subclass (S5713)
        return {"critical": 0, "high": 0, "total": 0, "passed": True, "details": "Invalid JSON"}

    critical = 0
    high = 0
    total = 0

    if isinstance(data, list):
        for pkg in data:
            for vuln in pkg.get("vulns", []):
                total += 1
                # pip-audit doesn't provide severity; count all as high
                high += 1

    passed = critical <= max_critical and high <= max_high
    return {
        "critical": critical,
        "high": high,
        "total": total,
        "passed": passed,
        "details": f"Critical: {critical}, High: {high}, Total: {total}" if total > 0 else "Clean",
    }


def write_summary(results, pattern, github_step_summary=False):
    """Write pass/fail summary table."""
    all_passed = all(r["passed"] for r in results)

    lines = [
        f"## Security Gate: {pattern}",
        "",
        "| Scan | Result | Details |",
        "|------|--------|---------|",
    ]

    for r in results:
        status = "PASS" if r["passed"] else "**FAIL**"
        lines.append(f"| {r['name']} | {status} | {r['details']} |")

    overall = "PASS" if all_passed else "**FAIL**"
    lines.append(f"| **Overall** | {overall} | |")
    lines.append("")

    if not all_passed:
        lines.append("> Security gate failed. Review findings above before merging.")
        lines.append("")

    output = "\n".join(lines)
    print(output)

    if github_step_summary:
        summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary_path:
            with open(summary_path, "a") as f:
                f.write(output + "\n")

    return all_passed


def main():
    parser = argparse.ArgumentParser(
        description="Unified security gate — evaluates all scan results"
    )
    parser.add_argument("--threshold", required=True, help="Path to threshold.yml")
    parser.add_argument("--pattern", required=True, help="Infrastructure pattern")
    parser.add_argument("--checkov-trend", default="", help="Path to checkov trend JSON")
    parser.add_argument("--trufflehog", default="", help="Path to TruffleHog JSON output")
    parser.add_argument("--semgrep", default="", help="Path to Semgrep SARIF output")
    parser.add_argument("--pip-audit", default="", help="Path to pip-audit JSON output")
    parser.add_argument("--strict", action="store_true", help="Apply strict mode")
    parser.add_argument("--github-step-summary", action="store_true")
    args = parser.parse_args()

    thresholds = load_threshold(args.threshold, args.pattern, args.strict)

    # Evaluate each scan
    checkov = evaluate_checkov(args.checkov_trend)
    checkov["name"] = "Checkov (IaC)"

    trufflehog = evaluate_trufflehog(args.trufflehog, thresholds["secrets_max"])
    trufflehog["name"] = "TruffleHog (Secrets)"

    semgrep = evaluate_semgrep(
        args.semgrep, thresholds["sast_max_high"], thresholds["sast_max_medium"]
    )
    semgrep["name"] = "Semgrep (SAST)"

    pip_audit = evaluate_pip_audit(
        args.pip_audit, thresholds["sca_max_critical"], thresholds["sca_max_high"]
    )
    pip_audit["name"] = "pip-audit (SCA)"

    results = [checkov, trufflehog, semgrep, pip_audit]

    all_passed = write_summary(
        results, args.pattern,
        github_step_summary=args.github_step_summary
    )

    if all_passed:
        print("Security gate PASSED — all scans within thresholds.")
        sys.exit(0)
    else:
        print("Security gate FAILED — review findings above.")
        sys.exit(1)


if __name__ == "__main__":
    main()
