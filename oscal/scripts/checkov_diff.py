#!/usr/bin/env python3
"""
Compare Checkov scan results against the accepted-risk baseline.

Reports new (unreviewed) findings, accepted (baselined) findings, and
resolved findings (in baseline but no longer reported by Checkov).

Exit code 1 if new findings exist (default) or threshold violated (with --threshold).

Usage:
    python3 oscal/scripts/checkov_diff.py \
        --checkov-results <results.json> \
        --baseline checkov-baseline.yml \
        --pattern ecs \
        --output-summary <trend.json> \
        [--threshold threshold.yml] \
        [--strict] \
        [--github-step-summary]
"""

import argparse
import json
import os
import sys
from datetime import datetime, date, timezone

import yaml


def load_baseline(path, pattern):
    """Load baseline YAML and filter findings by pattern.

    Returns two dicts:
    - active: findings with disposition accepted/deferred (still expected to fail)
    - all_findings: every finding for this pattern (for regression detection)
    """
    with open(path) as f:
        data = yaml.safe_load(f)

    active = {}
    all_findings = {}
    for entry in data.get("findings", []):
        if pattern in entry.get("patterns", []):
            all_findings[entry["check_id"]] = entry
            if entry.get("disposition") in ("accepted", "deferred", "discovered"):
                active[entry["check_id"]] = entry
    return active, all_findings


def load_checkov_results(path):
    """Load Checkov JSON results, handling both single-object and list formats."""
    with open(path) as f:
        data = json.load(f)

    if isinstance(data, list):
        result_sets = data
    else:
        result_sets = [data]

    passed_count = 0
    failed_checks = {}  # check_id -> list of check details

    for result_set in result_sets:
        summary = result_set.get("summary", {})
        passed_count += summary.get("passed", 0)

        for check in result_set.get("results", {}).get("failed_checks", []):
            check_id = check["check_id"]
            if check_id not in failed_checks:
                failed_checks[check_id] = []
            failed_checks[check_id].append({
                "resource": check.get("resource", "unknown"),
                "file_path": check.get("file_path", "unknown"),
                "check_name": check.get("check_result", {}).get("name", check.get("name", "")),
            })

    return passed_count, failed_checks


def compute_diff(active_baseline, all_findings, failed_checks):
    """Compute new, accepted, resolved, and regression finding sets.

    - new: failed in scan, not in active baseline (requires review)
    - accepted: failed in scan, in active baseline (expected)
    - resolved: in active baseline, not failed in scan (can be removed)
    - regressions: failed in scan, previously remediated/passing (flagged as new)
    """
    active_ids = set(active_baseline.keys())
    scan_ids = set(failed_checks.keys())
    remediated_ids = {
        cid for cid, entry in all_findings.items()
        if entry.get("disposition") in ("remediated", "passing")
    }

    accepted_ids = scan_ids & active_ids
    resolved_ids = active_ids - scan_ids
    regression_ids = scan_ids & remediated_ids
    # New = anything failed that isn't actively baselined (includes regressions)
    new_ids = scan_ids - active_ids

    return new_ids, accepted_ids, resolved_ids, regression_ids


def find_stale_reviews(active_baseline, today=None):
    """Find accepted/deferred findings past their next_review_date."""
    if today is None:
        today = date.today()
    stale = {}
    for cid, entry in active_baseline.items():
        next_review = entry.get("next_review_date")
        if next_review is None:
            continue
        try:
            review_date = date.fromisoformat(str(next_review))
            if review_date <= today:
                stale[cid] = entry
        except (ValueError, TypeError):
            pass
    return stale


def find_untriaged(active_baseline):
    """Find findings needing triage: discovered disposition or null reviewed_by/date."""
    untriaged = {}
    for cid, entry in active_baseline.items():
        if (entry.get("disposition") == "discovered"
                or entry.get("reviewed_by") is None
                or entry.get("reviewed_date") is None):
            untriaged[cid] = entry
    return untriaged


def deep_merge(base, override):
    """Recursively merge override dict into base dict. Returns new dict."""
    result = dict(base)
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_threshold(path, pattern, strict=False):
    """Load threshold.yml with defaults → pattern → strict layering.

    Returns flat dict: {"min_pass_rate": 85, "max_new": 0, ...}
    """
    with open(path) as f:
        data = yaml.safe_load(f)

    # Start with top-level defaults
    config = {
        "compliance": data.get("compliance", {}),
        "findings": data.get("findings", {}),
    }

    # Layer pattern-specific overrides
    patterns = data.get("patterns", {})
    if pattern in patterns:
        config = deep_merge(config, patterns[pattern])

    # Layer strict overrides
    if strict and "strict" in data:
        config = deep_merge(config, data["strict"])

    # Flatten to simple keys
    compliance = config.get("compliance", {})
    findings = config.get("findings", {})
    return {
        "min_pass_rate": compliance.get("min_pass_rate", 0),
        "max_new": findings.get("new", {}).get("max", -1),
        "max_regressions": findings.get("regressions", {}).get("max", -1),
        "max_untriaged": findings.get("untriaged", {}).get("max", -1),
        "max_stale_reviews": findings.get("stale_reviews", {}).get("max", -1),
        "max_total_failed": findings.get("total_failed", {}).get("max", -1),
    }


def evaluate_threshold(thresholds, passed, total_failed, new_count,
                       regression_count, untriaged_count, stale_count):
    """Compare actuals vs threshold limits.

    Returns list of (metric, actual, limit, passed) tuples.
    -1 limit means no limit (always passes, shown as SKIP).
    """
    total = passed + total_failed
    pass_rate = (passed / total * 100) if total > 0 else 0

    checks = [
        ("Pass Rate", pass_rate, thresholds["min_pass_rate"], "gte"),
        ("New Findings", new_count, thresholds["max_new"], "lte"),
        ("Regressions", regression_count, thresholds["max_regressions"], "lte"),
        ("Untriaged", untriaged_count, thresholds["max_untriaged"], "lte"),
        ("Stale Reviews", stale_count, thresholds["max_stale_reviews"], "lte"),
        ("Total Failed", total_failed, thresholds["max_total_failed"], "lte"),
    ]

    results = []
    for metric, actual, limit, direction in checks:
        if limit == -1:
            results.append((metric, actual, limit, True))  # SKIP
        elif direction == "gte":
            results.append((metric, actual, limit, actual >= limit))
        else:
            results.append((metric, actual, limit, actual <= limit))

    return results


def write_gate_summary(pattern, results, github_step_summary=False):
    """Write pass/fail table to stdout and optionally $GITHUB_STEP_SUMMARY."""
    all_passed = all(passed for _, _, _, passed in results)

    lines = [
        f"## Security Gate: {pattern}",
        "",
        "| Metric | Actual | Limit | Result |",
        "|---|---|---|---|",
    ]

    for metric, actual, limit, passed in results:
        if limit == -1:
            limit_str = "no limit"
            result_str = "SKIP"
        elif metric == "Pass Rate":
            limit_str = f"≥ {limit}%"
            result_str = "PASS" if passed else "FAIL"
        else:
            limit_str = f"≤ {limit}"
            result_str = "PASS" if passed else "FAIL"

        if metric == "Pass Rate":
            actual_str = f"{actual:.1f}%"
        else:
            actual_str = str(actual)

        lines.append(f"| {metric} | {actual_str} | {limit_str} | {result_str} |")

    overall = "PASS" if all_passed else "FAIL"
    lines.append(f"| **Result** | | | **{overall}** |")
    lines.append("")

    output = "\n".join(lines)
    print(output)

    if github_step_summary:
        summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary_path:
            with open(summary_path, "a") as f:
                f.write(output + "\n")

    return all_passed


# Map common Checkov check ID prefixes to NIST controls
CHECKOV_TO_NIST = {
    "CKV_AWS_1": "sc-7",      # Security groups
    "CKV_AWS_2": "sc-8",      # ALB HTTPS
    "CKV_AWS_3": "au-2",      # CloudTrail
    "CKV_AWS_5": "sc-7",      # Security groups
    "CKV_AWS_8": "sc-28",     # EBS encryption
    "CKV_AWS_17": "sc-28",    # RDS encryption
    "CKV_AWS_18": "au-2",     # S3 access logging
    "CKV_AWS_19": "sc-8",     # S3 SSL
    "CKV_AWS_23": "sc-7",     # Security groups
    "CKV_AWS_24": "ac-17",    # SSH restricted
    "CKV_AWS_26": "au-2",     # SNS encryption
    "CKV_AWS_33": "ia-5",     # KMS rotation
    "CKV_AWS_35": "au-2",     # CloudWatch logs
    "CKV_AWS_41": "ia-5",     # Secrets Manager
    "CKV_AWS_68": "sc-7",     # WAF
    "CKV_AWS_86": "au-2",     # CloudFront logging
    "CKV_AWS_145": "sc-28",   # S3 KMS encryption
    "CKV_AWS_158": "au-2",    # CloudWatch log encryption
    "CKV_AWS_252": "au-2",    # CloudTrail SNS
    "CKV_AWS_310": "cp-10",   # CloudFront failover
    "CKV_AWS_338": "au-11",   # Log retention
    "CKV_AWS_382": "cm-7",    # Read-only filesystem
    "CKV2_AWS_19": "sc-7",    # EIP association
    "CKV_AZURE_1": "sc-7",    # Network rules
    "CKV_AZURE_93": "sc-28",  # Managed disk encryption
    "CKV2_AZURE_1": "sc-7",   # Storage network rules
    "CKV2_AZURE_21": "au-2",  # Storage logging
    "CKV2_AZURE_32": "sc-7",  # Key Vault private endpoint
    "CKV2_AZURE_33": "sc-7",  # Storage private endpoint
    "CKV2_AZURE_40": "sc-7",  # Storage default deny
    "CKV2_AZURE_41": "ac-3",  # Managed identity
    "CKV2_AZURE_57": "cp-9",  # Geo-redundant backup
}


def update_baseline(baseline_path, pattern, new_ids, failed_checks):
    """Append newly discovered findings to the baseline YAML.

    New entries get disposition: discovered with null review fields.
    Returns the count of entries added.
    """
    with open(baseline_path) as f:
        data = yaml.safe_load(f)

    existing_ids = set()
    for entry in data.get("findings", []):
        if pattern in entry.get("patterns", []):
            existing_ids.add(entry["check_id"])

    today = date.today().isoformat()
    added = 0

    for cid in sorted(new_ids):
        if cid in existing_ids:
            continue

        nist = CHECKOV_TO_NIST.get(cid, "cm-2")
        count = len(failed_checks.get(cid, []))

        entry = {
            "check_id": cid,
            "disposition": "discovered",
            "category": "auto-discovered",
            "patterns": [pattern],
            "rationale": f"Auto-discovered by CI — needs triage",
            "expected_count": count,
            "nist_control": nist,
            "reviewed_by": None,
            "discovery_date": today,
            "reviewed_date": None,
            "next_review_date": None,
            "target_remediation_date": None,
            "remediated_date": None,
        }

        data.setdefault("findings", []).append(entry)
        added += 1
        print(f"  Added {cid} (discovered, {count} occurrence(s), {nist})")

    if added > 0:
        data["last_reviewed"] = today
        with open(baseline_path, "w") as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False,
                      allow_unicode=True)
        print(f"\n{added} new finding(s) added to {baseline_path}")
    else:
        print("\nNo new findings to add to baseline.")

    return added


def write_github_summary(pattern, passed, failed_checks, new_ids, accepted_ids,
                         resolved_ids, regression_ids, active_baseline,
                         all_findings, stale_reviews, untriaged):
    """Write markdown table to $GITHUB_STEP_SUMMARY."""
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return

    total_failed = sum(len(v) for v in failed_checks.values())
    total_new = sum(len(failed_checks[cid]) for cid in new_ids)
    total_accepted = sum(len(failed_checks[cid]) for cid in accepted_ids)
    total_regressions = sum(len(failed_checks[cid]) for cid in regression_ids)

    # Count resolved by expected_count from baseline
    total_resolved = sum(
        active_baseline[cid].get("expected_count", 1) for cid in resolved_ids
    )

    lines = [
        f"## Checkov Disposition: {pattern}",
        "",
        "| Passed | Failed | New | Accepted | Resolved | Regressions |",
        "|---|---|---|---|---|---|",
        f"| {passed} | {total_failed} | {total_new} | {total_accepted} "
        f"| {total_resolved} | {total_regressions} |",
        "",
    ]

    if regression_ids:
        lines.append("### Regressions (previously remediated/passing, now failing)")
        lines.append("")
        lines.append("| Check ID | Previous Status | Resource | File |")
        lines.append("|---|---|---|---|")
        for cid in sorted(regression_ids):
            prev = all_findings[cid].get("disposition", "unknown")
            for detail in failed_checks[cid]:
                lines.append(
                    f"| {cid} | {prev} | {detail['resource']} | {detail['file_path']} |"
                )
        lines.append("")

    non_regression_new = new_ids - regression_ids
    if non_regression_new:
        lines.append("### New Findings (require review)")
        lines.append("")
        lines.append("| Check ID | Resource | File |")
        lines.append("|---|---|---|")
        for cid in sorted(non_regression_new):
            for detail in failed_checks[cid]:
                lines.append(
                    f"| {cid} | {detail['resource']} | {detail['file_path']} |"
                )
        lines.append("")

    if resolved_ids:
        lines.append("### Resolved Findings (can be removed from baseline)")
        lines.append("")
        lines.append("| Check ID | Category | Rationale |")
        lines.append("|---|---|---|")
        for cid in sorted(resolved_ids):
            entry = active_baseline[cid]
            lines.append(
                f"| {cid} | {entry.get('category', '')} | {entry.get('rationale', '')} |"
            )
        lines.append("")

    if untriaged:
        lines.append("### Untriaged (missing reviewer or review date)")
        lines.append("")
        lines.append("| Check ID | Category | Disposition |")
        lines.append("|---|---|---|")
        for cid in sorted(untriaged.keys()):
            entry = untriaged[cid]
            lines.append(
                f"| {cid} | {entry.get('category', '')} | {entry.get('disposition', '')} |"
            )
        lines.append("")

    if stale_reviews:
        lines.append("### Stale Reviews (past next_review_date)")
        lines.append("")
        lines.append("| Check ID | Category | Review Due | Reviewed |")
        lines.append("|---|---|---|---|")
        for cid in sorted(stale_reviews.keys()):
            entry = stale_reviews[cid]
            lines.append(
                f"| {cid} | {entry.get('category', '')} "
                f"| {entry.get('next_review_date', '')} "
                f"| {entry.get('reviewed_date', '')} |"
            )
        lines.append("")

    with open(summary_path, "a") as f:
        f.write("\n".join(lines) + "\n")


def write_trend_json(output_path, pattern, passed, failed_checks, new_ids,
                     accepted_ids, resolved_ids, regression_ids,
                     active_baseline, stale_reviews, untriaged,
                     gate_results=None):
    """Write JSON trend summary for analytics."""
    total_failed = sum(len(v) for v in failed_checks.values())

    trend = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "pattern": pattern,
        "summary": {
            "passed": passed,
            "failed": total_failed,
            "new": sum(len(failed_checks[cid]) for cid in new_ids),
            "accepted": sum(len(failed_checks[cid]) for cid in accepted_ids),
            "resolved": sum(
                active_baseline[cid].get("expected_count", 1)
                for cid in resolved_ids
            ),
            "regressions": sum(
                len(failed_checks[cid]) for cid in regression_ids
            ),
            "stale_reviews": len(stale_reviews),
            "untriaged": len(untriaged),
        },
        "new_check_ids": sorted(new_ids),
        "resolved_check_ids": sorted(resolved_ids),
        "accepted_check_ids": sorted(accepted_ids),
        "regression_check_ids": sorted(regression_ids),
        "stale_review_check_ids": sorted(stale_reviews.keys()),
        "untriaged_check_ids": sorted(untriaged.keys()),
    }

    if gate_results is not None:
        trend["gate"] = {
            "passed": all(passed for _, _, _, passed in gate_results),
            "checks": [
                {
                    "metric": metric,
                    "actual": round(actual, 1) if isinstance(actual, float) else actual,
                    "limit": limit,
                    "passed": passed,
                }
                for metric, actual, limit, passed in gate_results
            ],
        }

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(trend, f, indent=2)

    return trend


def main():
    parser = argparse.ArgumentParser(
        description="Compare Checkov results against accepted-risk baseline"
    )
    parser.add_argument("--checkov-results", required=True,
                        help="Path to Checkov JSON results file")
    parser.add_argument("--baseline", required=True,
                        help="Path to checkov-baseline.yml")
    parser.add_argument("--pattern", required=True,
                        help="Infrastructure pattern to filter (e.g. ecs, ec2, azure-vm)")
    parser.add_argument("--output-summary", required=True,
                        help="Path to write trend JSON summary")
    parser.add_argument("--threshold",
                        help="Path to threshold.yml for security gate evaluation")
    parser.add_argument("--strict", action="store_true",
                        help="Apply strict mode overrides (for deploy workflows)")
    parser.add_argument("--github-step-summary", action="store_true",
                        help="Write markdown to $GITHUB_STEP_SUMMARY")
    parser.add_argument("--update-baseline", action="store_true",
                        help="Auto-add new findings to baseline as discovered (needs triage)")

    args = parser.parse_args()

    print(f"Loading baseline from {args.baseline} (pattern: {args.pattern})...")
    active_baseline, all_findings = load_baseline(args.baseline, args.pattern)
    print(f"  Active (accepted/deferred): {len(active_baseline)}, "
          f"Total tracked: {len(all_findings)}")

    print(f"Loading Checkov results from {args.checkov_results}...")
    passed, failed_checks = load_checkov_results(args.checkov_results)
    total_failed = sum(len(v) for v in failed_checks.values())
    print(f"  Passed: {passed}, Failed check IDs: {len(failed_checks)}, "
          f"Total failed: {total_failed}")

    if len(all_findings) == 0:
        print(f"\nNo baseline entries for pattern '{args.pattern}' — "
              f"skipping diff (run with pattern-specific findings to establish baseline).")
        # Still write trend JSON for visibility
        write_trend_json(
            args.output_summary, args.pattern, passed, failed_checks,
            set(), set(), set(), set(), active_baseline, {}, {}
        )
        sys.exit(0)

    new_ids, accepted_ids, resolved_ids, regression_ids = compute_diff(
        active_baseline, all_findings, failed_checks
    )
    stale_reviews = find_stale_reviews(active_baseline)
    untriaged = find_untriaged(active_baseline)

    print(f"  New: {len(new_ids)}, Accepted: {len(accepted_ids)}, "
          f"Resolved: {len(resolved_ids)}, Regressions: {len(regression_ids)}")
    if stale_reviews:
        print(f"  Stale reviews: {len(stale_reviews)}")
    if untriaged:
        print(f"  Untriaged: {len(untriaged)}")

    if regression_ids:
        print("\nRegressions (previously remediated/passing):")
        for cid in sorted(regression_ids):
            prev = all_findings[cid].get("disposition", "unknown")
            for detail in failed_checks[cid]:
                print(f"  {cid} (was {prev}): {detail['resource']} ({detail['file_path']})")

    non_regression_new = new_ids - regression_ids
    if non_regression_new:
        print("\nNew findings (not in baseline):")
        for cid in sorted(non_regression_new):
            for detail in failed_checks[cid]:
                print(f"  {cid}: {detail['resource']} ({detail['file_path']})")

    if resolved_ids:
        print("\nResolved findings (in baseline but not in scan):")
        for cid in sorted(resolved_ids):
            print(f"  {cid}: {active_baseline[cid].get('rationale', '')}")

    if stale_reviews:
        print("\nStale reviews (past next_review_date):")
        for cid in sorted(stale_reviews.keys()):
            entry = stale_reviews[cid]
            print(f"  {cid}: due {entry.get('next_review_date')}, "
                  f"last reviewed {entry.get('reviewed_date')}")

    if untriaged:
        print("\nUntriaged (missing reviewer or review date):")
        for cid in sorted(untriaged.keys()):
            print(f"  {cid}: needs initial triage")

    # Auto-update baseline with newly discovered findings
    if args.update_baseline and new_ids:
        update_baseline(args.baseline, args.pattern, new_ids, failed_checks)

    if args.github_step_summary:
        write_github_summary(
            args.pattern, passed, failed_checks,
            new_ids, accepted_ids, resolved_ids, regression_ids,
            active_baseline, all_findings, stale_reviews, untriaged
        )

    # Threshold evaluation
    gate_results = None
    if args.threshold:
        print(f"\nLoading threshold from {args.threshold} "
              f"(pattern: {args.pattern}, strict: {args.strict})...")
        thresholds = load_threshold(args.threshold, args.pattern, strict=args.strict)
        gate_results = evaluate_threshold(
            thresholds, passed, total_failed,
            len(new_ids), len(regression_ids), len(untriaged), len(stale_reviews)
        )

    trend = write_trend_json(
        args.output_summary, args.pattern, passed, failed_checks,
        new_ids, accepted_ids, resolved_ids, regression_ids,
        active_baseline, stale_reviews, untriaged, gate_results
    )
    print(f"\nTrend summary written to {args.output_summary}")

    # Exit logic: threshold mode vs legacy mode
    if args.threshold:
        gate_passed = write_gate_summary(
            args.pattern, gate_results,
            github_step_summary=args.github_step_summary
        )
        if gate_passed:
            print("Security gate PASSED.")
            sys.exit(0)
        else:
            print("Security gate FAILED — review findings above.")
            sys.exit(1)
    else:
        # Legacy behavior: exit 1 on any new findings
        if new_ids:
            reg_note = ""
            if regression_ids:
                reg_note = f" ({len(regression_ids)} regression(s))"
            print(f"\n{len(new_ids)} new finding(s) require review before merge.{reg_note}")
            sys.exit(1)
        else:
            print("\nNo new findings — all failed checks are baselined.")
            sys.exit(0)


if __name__ == "__main__":
    main()
# Auto-baseline support added (#72)
