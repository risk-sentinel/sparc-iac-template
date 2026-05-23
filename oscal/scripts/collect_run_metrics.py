#!/usr/bin/env python3
"""
Aggregate per-run compliance metrics across all scanners for time-series tracking.

Reads scanner outputs produced by the compliance workflow, optionally an AWS
Config compliance summary, and either (a) emits a standalone run-metrics.json
or (b) merges the metrics block into an existing pipeline-perf-history.json
entry keyed by run id.

What counts as a "check" per scanner:

  checkov       passed + failed  (real count — both pass and fail emit check rows)
  aws_config    compliant + non_compliant rule count (live from CLI)
  pip_audit     packages audited  (each package = one dependency check)
  semgrep       len(results)  (findings-only; SARIF does not emit rules-run count)
  trufflehog    len(lines)    (findings-only; default JSON does not emit files-scanned)

Semgrep and trufflehog "checks" are undercounts and are flagged as such in the
output. Trivy container scans live in build-runner.yml on a separate cadence
and are not included here. See docs/dev/metrics.md.

Usage:
    python3 oscal/scripts/collect_run_metrics.py \\
        --run-id "$GITHUB_RUN_ID" \\
        --timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \\
        --checkov-metadata-glob 'oscal-artifacts/metadata-*.json' \\
        --checkov-trend-glob 'oscal-artifacts/checkov-trend-*.json' \\
        --semgrep semgrep.sarif \\
        --trufflehog trufflehog.json \\
        --pip-audit pip-audit.json \\
        --aws-config aws-config-summary.json \\
        --history docs/dev/pipeline-perf-history.json \\
        --output run-metrics.json
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from datetime import datetime, timezone
from typing import Any


def _load_json(path: str) -> Any:
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError, ValueError):
        return None


def collect_checkov(metadata_glob: str, trend_glob: str) -> dict:
    """Sum passed/failed across per-pattern checkov metadata + checkov-trend files."""
    passed = failed = new = accepted = 0
    patterns = []

    for path in sorted(glob.glob(metadata_glob)) if metadata_glob else []:
        data = _load_json(path) or {}
        checkov = data.get("checkov", {})
        p = int(checkov.get("passed", 0) or 0)
        f = int(checkov.get("failed", 0) or 0)
        passed += p
        failed += f
        patterns.append(data.get("pattern") or os.path.basename(path))

    for path in sorted(glob.glob(trend_glob)) if trend_glob else []:
        data = _load_json(path) or {}
        summary = data.get("summary", {})
        new += int(summary.get("new", 0) or 0)
        accepted += int(summary.get("accepted", 0) or 0)

    return {
        "passed": passed,
        "failed": failed,
        "checks": passed + failed,
        "findings_failed": failed,
        "findings_new": new,
        "findings_accepted": accepted,
        "patterns": patterns,
    }


def collect_aws_config(path: str) -> dict | None:
    """Parse `aws configservice get-compliance-summary-by-config-rule` output."""
    data = _load_json(path)
    if data is None:
        return None
    summary = data.get("ComplianceSummary", {})
    compliant = int(summary.get("CompliantResourceCount", {}).get("CappedCount", 0) or 0)
    non_compliant = int(summary.get("NonCompliantResourceCount", {}).get("CappedCount", 0) or 0)
    # Rule-level counts when using get-compliance-summary-by-config-rule
    # (the response shape differs slightly — fall back to rule counts if present)
    if "CompliantRuleCount" in data:
        compliant = int(data.get("CompliantRuleCount", 0) or 0)
        non_compliant = int(data.get("NonCompliantRuleCount", 0) or 0)
    return {
        "compliant": compliant,
        "non_compliant": non_compliant,
        "checks": compliant + non_compliant,
        "findings": non_compliant,
    }


def collect_semgrep(path: str) -> dict | None:
    data = _load_json(path)
    if data is None:
        return None
    high = medium = low = 0
    for run in data.get("runs", []):
        for result in run.get("results", []):
            level = result.get("level", "note")
            if level == "error":
                high += 1
            elif level == "warning":
                medium += 1
            else:
                low += 1
    findings = high + medium + low
    return {
        "high": high,
        "medium": medium,
        "low": low,
        "findings": findings,
        # SARIF does not emit a rules-run count; "checks" undercounts actual work.
        "checks": findings,
        "checks_note": "findings-only; SARIF does not emit rules-run count",
    }


def collect_trufflehog(path: str) -> dict | None:
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path) as f:
            lines = [ln for ln in f if ln.strip()]
    except OSError:
        return None
    findings = len(lines)
    return {
        "findings": findings,
        # Default JSON output does not emit a files-scanned count.
        "checks": findings,
        "checks_note": "findings-only; default JSON does not emit files-scanned count",
    }


def collect_pip_audit(path: str) -> dict | None:
    data = _load_json(path)
    if data is None:
        return None
    packages = 0
    vulns = 0
    if isinstance(data, list):
        for pkg in data:
            packages += 1
            vulns += len(pkg.get("vulns", []) or [])
    elif isinstance(data, dict) and "dependencies" in data:
        # pip-audit newer schema variant
        for pkg in data.get("dependencies", []):
            packages += 1
            vulns += len(pkg.get("vulns", []) or [])
    return {
        "packages_audited": packages,
        "vulnerabilities": vulns,
        "checks": packages,
        "findings": vulns,
    }


def _sum_check_totals(scanners: dict) -> dict:
    total_checks = 0
    total_findings_failed = 0
    total_findings_new = 0
    total_findings_accepted = 0
    for name, block in scanners.items():
        if not block:
            continue
        total_checks += int(block.get("checks", 0) or 0)
        # Unified "findings_failed" semantics: anything that is a fail/regression/
        # vulnerability/secret across any scanner.
        if name == "checkov":
            total_findings_failed += int(block.get("findings_failed", 0) or 0)
            total_findings_new += int(block.get("findings_new", 0) or 0)
            total_findings_accepted += int(block.get("findings_accepted", 0) or 0)
        else:
            total_findings_failed += int(block.get("findings", 0) or 0)
    return {
        "checks": total_checks,
        "findings_failed": total_findings_failed,
        "findings_new": total_findings_new,
        "findings_accepted": total_findings_accepted,
    }


def build_metrics_block(args: argparse.Namespace) -> dict:
    scanners: dict[str, dict | None] = {
        "checkov": collect_checkov(args.checkov_metadata_glob, args.checkov_trend_glob),
        "aws_config": collect_aws_config(args.aws_config) if args.aws_config else None,
        "semgrep": collect_semgrep(args.semgrep) if args.semgrep else None,
        "trufflehog": collect_trufflehog(args.trufflehog) if args.trufflehog else None,
        "pip_audit": collect_pip_audit(args.pip_audit) if args.pip_audit else None,
    }
    # Drop None entries so the JSON clearly shows which scanners contributed.
    scanners = {k: v for k, v in scanners.items() if v}
    totals = _sum_check_totals(scanners)
    return {
        "scanners": scanners,
        "totals": totals,
    }


def update_history(history_path: str, run_id: str, timestamp: str, metrics: dict) -> None:
    """Merge the metrics block into the entry for this run_id, or create a new
    partial entry. Duration fields are left untouched — the chart script fills
    them in on a subsequent run via the GitHub API.
    """
    if os.path.exists(history_path):
        with open(history_path) as f:
            data = json.load(f)
    else:
        data = {
            "description": "Persistent pipeline performance time-series. Appended by CI on each successful compliance run.",
            "total_runs": 0,
            "runs": [],
        }

    runs = data.get("runs", [])
    # run_id may arrive as str from env; entries store it as int historically.
    try:
        rid: int | str = int(run_id)
    except (TypeError, ValueError):
        rid = run_id

    found = False
    for entry in runs:
        if entry.get("id") == rid:
            entry["metrics"] = metrics
            entry.setdefault("timestamp", timestamp)
            found = True
            break
    if not found:
        runs.append({
            "id": rid,
            "workflow": "FedRAMP 20x Compliance Validation",
            "timestamp": timestamp,
            "metrics": metrics,
        })
        runs.sort(key=lambda r: r.get("timestamp", ""))

    data["runs"] = runs
    data["total_runs"] = len(runs)
    data["last_updated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    os.makedirs(os.path.dirname(history_path) or ".", exist_ok=True)
    with open(history_path, "w") as f:
        json.dump(data, f, indent=2)


def main() -> int:
    parser = argparse.ArgumentParser(description="Aggregate per-run compliance metrics")
    parser.add_argument("--run-id", default=os.environ.get("GITHUB_RUN_ID", ""))
    parser.add_argument(
        "--timestamp",
        default=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    )
    parser.add_argument("--checkov-metadata-glob", default="")
    parser.add_argument("--checkov-trend-glob", default="")
    parser.add_argument("--semgrep", default="")
    parser.add_argument("--trufflehog", default="")
    parser.add_argument("--pip-audit", default="")
    parser.add_argument("--aws-config", default="")
    parser.add_argument("--history", default="", help="Merge into this pipeline-perf-history.json")
    parser.add_argument("--output", default="run-metrics.json", help="Write standalone metrics file")
    parser.add_argument("--github-step-summary", action="store_true")
    args = parser.parse_args()

    metrics = build_metrics_block(args)

    run_metrics = {
        "run_id": args.run_id,
        "timestamp": args.timestamp,
        "commit": os.environ.get("GITHUB_SHA", "unknown")[:7],
        "branch": os.environ.get("GITHUB_REF_NAME", "unknown"),
        "metrics": metrics,
    }

    with open(args.output, "w") as f:
        json.dump(run_metrics, f, indent=2)
    print(f"Wrote {args.output}")

    if args.history and args.run_id:
        update_history(args.history, args.run_id, args.timestamp, metrics)
        print(f"Merged metrics into {args.history} for run_id={args.run_id}")

    totals = metrics["totals"]
    line = (
        f"Checks: {totals['checks']} | "
        f"Findings (failed/new/accepted): "
        f"{totals['findings_failed']}/{totals['findings_new']}/{totals['findings_accepted']}"
    )
    print(line)

    if args.github_step_summary:
        summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary_path:
            with open(summary_path, "a") as f:
                f.write("## Run Metrics\n\n")
                f.write("| Metric | Value |\n|---|---|\n")
                f.write(f"| Total checks | {totals['checks']} |\n")
                f.write(f"| Findings (failed) | {totals['findings_failed']} |\n")
                f.write(f"| Findings (new / unaccepted) | {totals['findings_new']} |\n")
                f.write(f"| Findings (accepted risk) | {totals['findings_accepted']} |\n")
                contributors = ", ".join(metrics["scanners"].keys()) or "none"
                f.write(f"| Contributing scanners | {contributors} |\n\n")
                f.write(
                    "Throughput (checks/min) is computed by the chart script after "
                    "the workflow finishes and duration is known.\n"
                )

    return 0


if __name__ == "__main__":
    sys.exit(main())
