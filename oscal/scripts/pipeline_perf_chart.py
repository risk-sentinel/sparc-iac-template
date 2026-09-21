#!/usr/bin/env python3
"""
Generate pipeline performance XmR control chart with pre/post optimization phases.

Uses Individuals and Moving Range (XmR) chart — appropriate for process data
that is not normally distributed. Control limits derived from average moving
range (mR-bar) rather than standard deviation.

Data source: a persistent time-series file that accumulates one entry per
successful workflow run. On each CI invocation this script appends the latest
runs from the GitHub API (deduplicated by run ID) so the history grows over
time and is never lost to API pagination limits.

The canonical history lives in S3, NOT in this repo (#615):

    s3://your-security-artifacts-bucket/sparc/latest/sparc-iac/pipeline-perf-history.json

CI fetches it to ``perf-history.json`` before running this script and uploads
it back afterwards (main only). It used to be committed to ``docs/dev/`` on
every run, which pushed a commit to ``main`` each time — and with
``strict_required_status_checks_policy`` that forced an Update-branch plus a
full CI re-run on every open PR.

Note this script is a *writer* as well as a reader: it merges fresh API runs
into the history and saves it back, so always point ``--history`` at the
S3-sourced copy.

Usage:
    python3 oscal/scripts/pipeline_perf_chart.py \
        --baseline docs/dev/pipeline-baseline.json \
        --output pipeline-performance.png \
        [--history perf-history.json] \
        [--recent 200]
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import matplotlib.dates as mdates
except ImportError:
    print("matplotlib not installed. Install with: pip install matplotlib")
    sys.exit(1)

# Working-tree filename, NOT a repo path (#615). The canonical history lives in
# S3; CI fetches it here first. Defaulting to docs/dev/ would let a local run
# silently recreate a stale in-repo copy of a file that is no longer tracked.
HISTORY_PATH = "perf-history.json"


def get_recent_runs(limit=1000):
    """Pull recent successful runs from GitHub API via gh CLI.

    All runs, all triggers — reflects real-world user experience.
    """
    result = subprocess.run(
        ['gh', 'run', 'list', '--repo', 'risk-sentinel/sparc-iac',
         # coerce to int so the arg can't carry an injection — sonar S8705 (#526)
         '--limit', str(int(limit)),
         '--json', 'databaseId,name,createdAt,updatedAt,conclusion'],
        capture_output=True, text=True
    )
    # Degrade gracefully on a transient gh failure (rate limit, auth/permission
    # hiccup, network blip) — empty/non-JSON stdout must not crash the chart;
    # fall back to the persistent history only. Mirrors pipeline_perf_compare (#321).
    if result.returncode != 0 or not result.stdout.strip():
        sys.stderr.write(
            "warning: `gh run list` returned no data "
            f"(exit={result.returncode}); continuing with existing history only.\n"
        )
        return []
    runs = json.loads(result.stdout)

    filtered = []
    for run in runs:
        if run['conclusion'] != 'success' or 'Claude' in run['name']:
            continue
        created = datetime.fromisoformat(run['createdAt'].replace('Z', '+00:00'))
        updated = datetime.fromisoformat(run['updatedAt'].replace('Z', '+00:00'))
        duration_sec = (updated - created).total_seconds()
        if duration_sec > 1800 or duration_sec < 1:
            continue
        filtered.append({
            'id': run['databaseId'],
            'workflow': run['name'],
            'timestamp': run['createdAt'],
            'duration_sec': round(duration_sec),
            'duration_min': round(duration_sec / 60, 2),
        })
    return filtered


def load_history(history_path):
    """Load the persistent history file, return list of run dicts."""
    if os.path.exists(history_path):
        try:
            with open(history_path) as f:
                data = json.load(f)
            return data.get('runs', [])
        except (json.JSONDecodeError, OSError):
            return []
    return []


def merge_and_save_history(history_path, existing, new_runs):
    """Merge new API runs into existing history, sort chronologically, write back.

    Dict-update by run id so metrics added by collect_run_metrics.py (which may
    land before duration is known) are preserved when the API duration arrives.

    Returns the merged list.
    """
    by_id = {r['id']: dict(r) for r in existing}
    added = 0
    for run in new_runs:
        rid = run['id']
        if rid in by_id:
            # Preserve fields already in the entry (e.g. metrics) and fill in
            # anything the API provides that's missing (e.g. duration_sec).
            for k, v in run.items():
                by_id[rid].setdefault(k, v)
        else:
            by_id[rid] = dict(run)
            added += 1
    merged = sorted(by_id.values(), key=lambda x: x.get('timestamp', ''))

    output = {
        'description': 'Persistent pipeline performance time-series. Appended by CI on each successful compliance run.',
        'last_updated': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'total_runs': len(merged),
        'runs': merged,
    }
    os.makedirs(os.path.dirname(history_path) or '.', exist_ok=True)
    with open(history_path, 'w') as f:
        json.dump(output, f, indent=2)

    if added:
        print(f"History: appended {added} new runs ({len(merged)} total)")
    else:
        print(f"History: no new runs to append ({len(merged)} total)")

    return merged


def calc_xmr(durations):
    """Calculate XmR control limits and moving ranges.

    Returns: (x_bar, ucl, lcl, mr_bar, mr_ucl, moving_ranges)
    UCL = X-bar + 2.66 * mR-bar  (2.66 = 3/d2, d2=1.128 for n=2)
    mR UCL = D4 * mR-bar  (D4 = 3.267 for n=2)
    """
    if len(durations) < 2:
        mean = durations[0] if durations else 0
        return mean, mean, 0, 0, 0, []

    x_bar = sum(durations) / len(durations)
    moving_ranges = [abs(durations[i] - durations[i - 1]) for i in range(1, len(durations))]
    mr_bar = sum(moving_ranges) / len(moving_ranges)

    ucl = x_bar + 2.66 * mr_bar
    lcl = max(0, x_bar - 2.66 * mr_bar)
    mr_ucl = 3.267 * mr_bar

    return x_bar, ucl, lcl, mr_bar, mr_ucl, moving_ranges


def _metrics_rows(all_runs, target_wf):
    """Extract (timestamp, metrics_totals, duration_sec) tuples for target workflow.

    Only runs with BOTH a `metrics.totals.checks` and a `duration_sec` contribute
    to throughput. Runs with `metrics.totals` but no duration still contribute
    to the findings trend — we just can't compute checks/min for them yet.
    """
    rows = []
    for run in all_runs:
        if run.get('workflow') != target_wf:
            continue
        metrics = run.get('metrics') or {}
        totals = metrics.get('totals') or {}
        if not totals:
            continue
        ts = datetime.fromisoformat(run['timestamp'].replace('Z', '+00:00'))
        rows.append({
            'timestamp': ts,
            'checks': int(totals.get('checks', 0) or 0),
            'findings_failed': int(totals.get('findings_failed', 0) or 0),
            'findings_new': int(totals.get('findings_new', 0) or 0),
            'findings_accepted': int(totals.get('findings_accepted', 0) or 0),
            'duration_sec': int(run.get('duration_sec') or 0),
        })
    rows.sort(key=lambda r: r['timestamp'])
    return rows


def generate_chart(baseline_data, all_runs, output_path):  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
    """Generate XmR control chart with pre/post optimization phases."""
    target_wf = 'FedRAMP 20x Compliance Validation'

    # Phase boundaries
    baseline_ts = baseline_data.get('generated', '')
    cutover = datetime.fromisoformat(baseline_ts.replace('Z', '+00:00')) if baseline_ts else datetime.now(timezone.utc)
    # Containerized pipeline deployed Apr 3, 2026
    container_cutover = datetime(2026, 4, 3, 18, 0, tzinfo=timezone.utc)

    # Pre-optimization from baseline
    pre = []
    for run in baseline_data.get('runs', []):
        if run['workflow'] == target_wf:
            ts = datetime.fromisoformat(run['date'] + 'T' + run.get('time', '00:00') + ':00+00:00')
            pre.append({'timestamp': ts, 'duration_min': run['duration_sec'] / 60})
    pre.sort(key=lambda x: x['timestamp'])

    # Convert history timestamps to datetime objects. Entries without
    # duration_sec are possible now that collect_run_metrics.py can write a
    # metrics-only entry before the workflow finishes (the API-sourced duration
    # lands on a subsequent run's chart merge). Skip those for the duration
    # panels; _metrics_rows reads from all_runs directly and will still include
    # them in the findings panel.
    recent_runs = []
    for run in all_runs:
        duration_sec = run.get('duration_sec')
        if duration_sec is None:
            continue
        ts = datetime.fromisoformat(run['timestamp'].replace('Z', '+00:00'))
        recent_runs.append({
            'workflow': run.get('workflow', ''),
            'timestamp': ts,
            'duration_sec': duration_sec,
            'duration_min': run.get('duration_min', duration_sec / 60.0),
        })

    # Post-optimization (before container)
    post = [r for r in recent_runs if r['workflow'] == target_wf and cutover < r['timestamp'] <= container_cutover]
    post.sort(key=lambda x: x['timestamp'])

    # Containerized pipeline
    container = [r for r in recent_runs if r['workflow'] == target_wf and r['timestamp'] > container_cutover]
    container.sort(key=lambda x: x['timestamp'])

    pre_vals = [r['duration_min'] for r in pre]
    post_vals = [r['duration_min'] for r in post]
    container_vals = [r['duration_min'] for r in container]

    pre_xbar, pre_ucl, pre_lcl, pre_mr_bar, pre_mr_ucl, pre_mr = calc_xmr(pre_vals)
    post_xbar, post_ucl, post_lcl, post_mr_bar, post_mr_ucl, post_mr = calc_xmr(post_vals) if post_vals else (0, 0, 0, 0, 0, [])
    cont_xbar, cont_ucl, cont_lcl, cont_mr_bar, cont_mr_ucl, cont_mr = calc_xmr(container_vals) if container_vals else (0, 0, 0, 0, 0, [])

    # --- Figure: 5 panels (duration X, duration mR, by-workflow bar, throughput XmR, findings trend) ---
    fig, (ax_x, ax_mr, ax_bar, ax_tp, ax_find) = plt.subplots(
        5, 1, figsize=(14, 20), height_ratios=[3, 2, 1.5, 2.5, 2.5],
    )
    fig.suptitle('Pipeline Performance & Findings\nFedRAMP 20x Compliance Validation — duration, throughput, findings over time',
                 fontsize=14, fontweight='bold')

    # === Panel 1: Individuals (X) Chart ===
    if pre:
        t = [r['timestamp'] for r in pre]
        ax_x.plot(t, pre_vals, 'o-', color='#d73a49', alpha=0.6, markersize=4, linewidth=0.8,
                  label=f'Pre (n={len(pre)}, X\u0304={pre_xbar:.1f}m)')
        ax_x.axhline(pre_xbar, color='#d73a49', linestyle='-', alpha=0.4, linewidth=1.5)
        ax_x.axhline(pre_ucl, color='#d73a49', linestyle='--', alpha=0.3, label=f'UCL={pre_ucl:.1f}m')
        ax_x.axhline(pre_lcl, color='#d73a49', linestyle='--', alpha=0.3, label=f'LCL={pre_lcl:.1f}m')

    if post:
        t = [r['timestamp'] for r in post]
        ax_x.plot(t, post_vals, 'o-', color='#2ea44f', alpha=0.6, markersize=4, linewidth=0.8,
                  label=f'Post (n={len(post)}, X\u0304={post_xbar:.1f}m)')
        ax_x.axhline(post_xbar, color='#2ea44f', linestyle='-', alpha=0.4, linewidth=1.5)
        ax_x.axhline(post_ucl, color='#2ea44f', linestyle='--', alpha=0.3)
        ax_x.axhline(post_lcl, color='#2ea44f', linestyle='--', alpha=0.3)

    if container:
        t = [r['timestamp'] for r in container]
        ax_x.plot(t, container_vals, 'o-', color='#6f42c1', alpha=0.6, markersize=4, linewidth=0.8,
                  label=f'Container (n={len(container)}, X\u0304={cont_xbar:.1f}m)')
        ax_x.axhline(cont_xbar, color='#6f42c1', linestyle='-', alpha=0.4, linewidth=1.5)
        ax_x.axhline(cont_ucl, color='#6f42c1', linestyle='--', alpha=0.3)
        ax_x.axhline(cont_lcl, color='#6f42c1', linestyle='--', alpha=0.3)

    ax_x.axvline(cutover, color='#4a9eff', linestyle='--', linewidth=2, label='Optimization deployed')
    ax_x.axvline(container_cutover, color='#6f42c1', linestyle='--', linewidth=2, label='Containerized pipeline')
    ax_x.set_ylabel('Duration (minutes)')
    ax_x.set_title('Individuals (X) Chart', fontsize=10, loc='left')
    ax_x.legend(loc='upper right', fontsize=8)
    ax_x.grid(True, alpha=0.2)
    ax_x.xaxis.set_major_formatter(mdates.DateFormatter('%m/%d %H:%M'))
    plt.setp(ax_x.xaxis.get_majorticklabels(), rotation=45, ha='right')

    # === Panel 2: Moving Range (mR) Chart ===
    if pre_mr:
        t = [pre[i]['timestamp'] for i in range(1, len(pre))]
        ax_mr.plot(t, pre_mr, 'o-', color='#d73a49', alpha=0.6, markersize=3, linewidth=0.8,
                   label=f'Pre mR\u0304={pre_mr_bar:.2f}m')
        ax_mr.axhline(pre_mr_bar, color='#d73a49', linestyle='-', alpha=0.4, linewidth=1.5)
        ax_mr.axhline(pre_mr_ucl, color='#d73a49', linestyle='--', alpha=0.3,
                      label=f'UCL={pre_mr_ucl:.1f}m')

    if post_mr:
        t = [post[i]['timestamp'] for i in range(1, len(post))]
        ax_mr.plot(t, post_mr, 'o-', color='#2ea44f', alpha=0.6, markersize=3, linewidth=0.8,
                   label=f'Post mR\u0304={post_mr_bar:.2f}m')
        ax_mr.axhline(post_mr_bar, color='#2ea44f', linestyle='-', alpha=0.4, linewidth=1.5)
        ax_mr.axhline(post_mr_ucl, color='#2ea44f', linestyle='--', alpha=0.3)

    if cont_mr:
        t = [container[i]['timestamp'] for i in range(1, len(container))]
        ax_mr.plot(t, cont_mr, 'o-', color='#6f42c1', alpha=0.6, markersize=3, linewidth=0.8,
                   label=f'Container mR\u0304={cont_mr_bar:.2f}m')
        ax_mr.axhline(cont_mr_bar, color='#6f42c1', linestyle='-', alpha=0.4, linewidth=1.5)
        ax_mr.axhline(cont_mr_ucl, color='#6f42c1', linestyle='--', alpha=0.3)

    ax_mr.axvline(cutover, color='#4a9eff', linestyle='--', linewidth=2)
    ax_mr.axvline(container_cutover, color='#6f42c1', linestyle='--', linewidth=2)
    ax_mr.axhline(0, color='black', linewidth=0.5)
    ax_mr.set_ylabel('Moving Range (min)')
    ax_mr.set_title('Moving Range (mR) Chart', fontsize=10, loc='left')
    ax_mr.legend(loc='upper right', fontsize=8)
    ax_mr.grid(True, alpha=0.2)
    ax_mr.xaxis.set_major_formatter(mdates.DateFormatter('%m/%d %H:%M'))
    plt.setp(ax_mr.xaxis.get_majorticklabels(), rotation=45, ha='right')

    # === Panel 3: Summary bar chart (all workflows) ===
    pre_summary = baseline_data.get('by_workflow', {})
    post_summary = {}
    for run in recent_runs:
        if run['timestamp'] > cutover:
            wf = run['workflow']
            post_summary.setdefault(wf, []).append(run['duration_sec'])

    wf_names = sorted(set(list(pre_summary.keys()) + list(post_summary.keys())))
    x_pos = range(len(wf_names))
    width = 0.35

    pre_avgs = [pre_summary.get(wf, {}).get('avg_sec', 0) / 60 for wf in wf_names]
    post_avgs = []
    for wf in wf_names:
        if wf in post_summary and post_summary[wf]:
            post_avgs.append(sum(post_summary[wf]) / len(post_summary[wf]) / 60)
        else:
            post_avgs.append(0)

    bars1 = ax_bar.bar([x - width / 2 for x in x_pos], pre_avgs, width,
                       label='Before', color='#d73a49', alpha=0.7)
    bars2 = ax_bar.bar([x + width / 2 for x in x_pos], post_avgs, width,
                       label='After', color='#2ea44f', alpha=0.7)
    ax_bar.set_ylabel('Avg (min)')
    ax_bar.set_xticks(list(x_pos))
    ax_bar.set_xticklabels([n.replace('FedRAMP 20x ', '').replace(' Validation', '')
                            for n in wf_names], fontsize=8, rotation=30, ha='right')
    ax_bar.legend(fontsize=9)
    ax_bar.grid(True, alpha=0.2, axis='y')
    for bar in bars1 + bars2:
        if bar.get_height() > 0:
            ax_bar.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.05,
                        f'{bar.get_height():.1f}m', ha='center', va='bottom', fontsize=7)

    # === Panel 4: Throughput (checks/min) XmR Chart ===
    # Read from the raw history (all_runs) so metrics-only entries (collector
    # wrote metrics but duration hasn't landed yet) still appear in the
    # findings panel. recent_runs is the transformed list used only for the
    # duration panels above.
    metrics_rows = _metrics_rows(all_runs, target_wf)
    throughput_rows = [
        {
            'timestamp': r['timestamp'],
            'checks_per_min': (r['checks'] / (r['duration_sec'] / 60.0)) if r['duration_sec'] > 0 else 0,
        }
        for r in metrics_rows if r['duration_sec'] > 0 and r['checks'] > 0
    ]
    if throughput_rows:
        t = [r['timestamp'] for r in throughput_rows]
        vals = [r['checks_per_min'] for r in throughput_rows]
        tp_xbar, tp_ucl, tp_lcl, tp_mr_bar, tp_mr_ucl, _ = calc_xmr(vals)
        ax_tp.plot(t, vals, 'o-', color='#2188ff', alpha=0.7, markersize=4, linewidth=0.8,
                   label=f'n={len(vals)}, X̄={tp_xbar:.0f} checks/min')
        ax_tp.axhline(tp_xbar, color='#2188ff', linestyle='-', alpha=0.4, linewidth=1.5)
        ax_tp.axhline(tp_ucl, color='#2188ff', linestyle='--', alpha=0.3, label=f'UCL={tp_ucl:.0f}')
        ax_tp.axhline(tp_lcl, color='#2188ff', linestyle='--', alpha=0.3, label=f'LCL={tp_lcl:.0f}')
        ax_tp.xaxis.set_major_formatter(mdates.DateFormatter('%m/%d %H:%M'))
        plt.setp(ax_tp.xaxis.get_majorticklabels(), rotation=45, ha='right')
        ax_tp.legend(loc='upper right', fontsize=8)
    else:
        ax_tp.text(0.5, 0.5, 'No throughput data yet — metrics tracking begins on first post-#133 run',
                   transform=ax_tp.transAxes, ha='center', va='center', color='#666', fontsize=10)
    ax_tp.set_ylabel('Checks / minute')
    ax_tp.set_title('Throughput XmR (all scanners combined)', fontsize=10, loc='left')
    ax_tp.grid(True, alpha=0.2)

    # === Panel 5: Findings over time — stacked area (accepted + new) with failed overlay ===
    if metrics_rows:
        t = [r['timestamp'] for r in metrics_rows]
        accepted = [r['findings_accepted'] for r in metrics_rows]
        new = [r['findings_new'] for r in metrics_rows]
        failed = [r['findings_failed'] for r in metrics_rows]
        ax_find.stackplot(
            t, accepted, new,
            labels=['Accepted risk (reviewed)', 'New / unaccepted'],
            colors=['#6e7781', '#d73a49'], alpha=0.55,
        )
        # Overlay total failed (includes non-checkov scanners where new/accepted split is unavailable).
        ax_find.plot(t, failed, 'o-', color='#24292e', alpha=0.7, markersize=3, linewidth=1.0,
                     label='Total findings (all scanners)')
        ax_find.xaxis.set_major_formatter(mdates.DateFormatter('%m/%d %H:%M'))
        plt.setp(ax_find.xaxis.get_majorticklabels(), rotation=45, ha='right')
        ax_find.legend(loc='upper right', fontsize=8)
    else:
        ax_find.text(0.5, 0.5, 'No findings data yet — metrics tracking begins on first post-#133 run',
                     transform=ax_find.transAxes, ha='center', va='center', color='#666', fontsize=10)
    ax_find.set_ylabel('Findings')
    ax_find.set_title('Findings Over Time — accepted (grey) + new (red) stacked; total as line', fontsize=10, loc='left')
    ax_find.grid(True, alpha=0.2)

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    print(f"Chart saved to {output_path}")

    if pre_vals and post_vals:
        change = ((post_xbar - pre_xbar) / pre_xbar) * 100
        print(f"\nCompliance: {pre_xbar:.1f}m -> {post_xbar:.1f}m ({change:+.1f}%)")
    elif pre_vals:
        print(f"\nBaseline: {len(pre_vals)} pre-optimization runs. Rerun after 60+ post runs.")


def main():
    parser = argparse.ArgumentParser(description="Pipeline performance XmR control chart")
    parser.add_argument("--baseline", required=True)
    # Working-tree filename (#615) — the chart is no longer committed to docs/dev/.
    parser.add_argument("--output", default="pipeline-performance.png")
    parser.add_argument("--history", default=HISTORY_PATH)
    parser.add_argument("--recent", type=int, default=200)
    args = parser.parse_args()

    with open(args.baseline) as f:
        baseline = json.load(f)

    print(f"Baseline: {baseline['generated']} ({baseline['total_runs']} runs)")

    # 1. Load persistent history
    history = load_history(args.history)
    print(f"History: {len(history)} existing runs")

    # 2. Pull latest from API and merge into history
    api_runs = get_recent_runs(args.recent)
    print(f"API: {len(api_runs)} recent runs")
    all_runs = merge_and_save_history(args.history, history, api_runs)

    # 3. Generate chart from full history
    generate_chart(baseline, all_runs, args.output)


if __name__ == "__main__":
    main()
