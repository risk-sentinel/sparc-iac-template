#!/usr/bin/env python3
"""
Compare pipeline performance across three phases:
  1. Pre-optimization (from baseline JSON)
  2. Post-optimization (baseline date → container cutover)
  3. Containerized pipeline (after container cutover)

Usage:
    python3 oscal/scripts/pipeline_perf_compare.py \
        --baseline docs/dev/pipeline-baseline.json \
        --recent 60
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone


# Container pipeline deployed Apr 3, 2026 18:00 UTC
CONTAINER_CUTOVER = datetime(2026, 4, 3, 18, 0, tzinfo=timezone.utc)


def get_recent_runs(limit=60):
    """Pull recent successful runs from GitHub API via gh CLI."""
    result = subprocess.run(
        ['gh', 'run', 'list', '--repo', 'risk-sentinel/sparc-iac',
         '--limit', str(limit * 3),  # overfetch to filter
         '--json', 'databaseId,name,createdAt,updatedAt,conclusion,status'],
        capture_output=True, text=True
    )
    runs = json.loads(result.stdout)

    filtered = []
    for run in runs:
        if run['conclusion'] != 'success':
            continue
        if 'Claude' in run['name']:
            continue

        created = datetime.fromisoformat(run['createdAt'].replace('Z', '+00:00'))
        updated = datetime.fromisoformat(run['updatedAt'].replace('Z', '+00:00'))
        duration_sec = (updated - created).total_seconds()

        if duration_sec > 1800:
            continue

        filtered.append({
            'workflow': run['name'],
            'timestamp': created,
            'duration_sec': round(duration_sec),
        })

        if len(filtered) >= limit:
            break

    return filtered


def summarize(runs):
    """Summarize runs by workflow."""
    by_wf = {}
    for run in runs:
        wf = run['workflow']
        if wf not in by_wf:
            by_wf[wf] = []
        by_wf[wf].append(run['duration_sec'])

    summary = {}
    for wf, durations in by_wf.items():
        durations.sort()
        count = len(durations)
        summary[wf] = {
            'count': count,
            'avg_sec': round(sum(durations) / count),
            'median_sec': durations[count // 2],
            'min_sec': durations[0],
            'max_sec': durations[-1],
        }
    return summary


def fmt_phase(summary, wf):
    """Format a phase cell."""
    s = summary.get(wf, {})
    if not s:
        return "—"
    return f"{s['avg_sec']}s ({s['count']})"


def main():
    parser = argparse.ArgumentParser(description="Compare pipeline performance across phases")
    parser.add_argument("--baseline", required=True, help="Path to baseline JSON")
    parser.add_argument("--recent", type=int, default=60, help="Number of recent runs")
    args = parser.parse_args()

    with open(args.baseline) as f:
        baseline = json.load(f)

    baseline_ts = baseline.get('generated', '')
    cutover = datetime.fromisoformat(baseline_ts.replace('Z', '+00:00')) if baseline_ts else CONTAINER_CUTOVER

    print(f"Baseline: {baseline['generated']} ({baseline['total_runs']} runs)")
    print(f"Optimization cutover: {cutover.strftime('%Y-%m-%d')}")
    print(f"Container cutover: {CONTAINER_CUTOVER.strftime('%Y-%m-%d')}")
    print(f"Collecting {args.recent} recent runs...\n")

    recent = get_recent_runs(args.recent)

    # Split into phases
    post_runs = [r for r in recent if cutover < r['timestamp'] <= CONTAINER_CUTOVER]
    container_runs = [r for r in recent if r['timestamp'] > CONTAINER_CUTOVER]

    pre = baseline['by_workflow']
    post = summarize(post_runs)
    cont = summarize(container_runs)

    all_wfs = sorted(set(list(pre.keys()) + list(post.keys()) + list(cont.keys())))

    print("| Workflow | Pre-Opt (avg) | Post-Opt (avg) | Container (avg) | Total Change |")
    print("|----------|--------------|----------------|-----------------|-------------|")

    for wf in all_wfs:
        p = pre.get(wf, {})
        pre_avg = p.get('avg_sec', 0)
        pre_cell = f"{pre_avg}s ({p.get('count', 0)})" if pre_avg else "—"

        post_cell = fmt_phase(post, wf)
        cont_cell = fmt_phase(cont, wf)

        # Calculate total change (pre vs container)
        cont_avg = cont.get(wf, {}).get('avg_sec', 0)
        if pre_avg > 0 and cont_avg > 0:
            change_pct = round((cont_avg - pre_avg) / pre_avg * 100)
            change_str = f"{change_pct:+d}%"
        else:
            change_str = "—"

        print(f"| {wf} | {pre_cell} | {post_cell} | {cont_cell} | {change_str} |")


if __name__ == "__main__":
    main()
