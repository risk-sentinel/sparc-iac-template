# Pipeline Metrics

The FedRAMP 20x compliance pipeline emits a structured per-run metrics record covering every scanner, accumulated over time in `s3://your-security-artifacts-bucket/perf/pipeline-perf-history.json` and rendered as trend panels in `pipeline-performance.png`.

> **Where to see the chart (#615).** The history and chart are **no longer committed to this repo**. Every compliance run publishes the chart to its **job summary** and attaches it as the `pipeline-performance-chart` artifact (30-day retention); runs on `main` also upload it to `s3://your-security-artifacts-bucket/latest/pipeline-performance.png`. A durable browsable URL is tracked in #616.
>
> Committing them here meant every run on `main` pushed a commit to `main`, and because the branch ruleset sets `strict_required_status_checks_policy: true`, that forced an Update-branch plus a full CI re-run on **every open PR** — roughly six times a day. The data was already being uploaded to S3, so the in-repo copy was pure duplication.

Tracks three dimensions:

1. **Duration** (wall-clock minutes per workflow run) — existing, pre-#133.
2. **Throughput** (total checks ÷ duration) — new in #133. Shows efficiency gains even as the number of patterns or scanners grows.
3. **Findings over time** (failed / new / accepted-risk counts) — new in #133. The DevSecOps story: volume trending down or flat while new-finding load stays near zero means the security posture is holding as scope grows.

## Data flow

```
validate-and-scan  →  produces  semgrep.sarif, trufflehog.json, pip-audit.json
  (compliance.yml)              (uploaded as  security-scan-results  artifact)

checkov-scan       →  produces  metadata-<pattern>.json  (passed/failed),
  (per-pattern                   checkov-trend-<pattern>.json  (new/accepted)
   matrix)                      (uploaded as  oscal-<pattern>  artifact)

post-scan          →  downloads both bundles
  (compliance.yml)  →  fetches  AWS Config  describe-compliance-by-config-rule
                    →  FETCHES  perf-history.json  FROM S3  (fails closed if absent)
                    →  runs    oscal/scripts/collect_run_metrics.py
                    →  writes  run-metrics.json   (per-run, S3-archived)
                             + perf-history.json   (appended)
                    →  runs    oscal/scripts/pipeline_perf_chart.py
                             (also merges GitHub API runs INTO perf-history.json)
                    →  writes  pipeline-performance.png    (5 panels)
                    →  job summary + build artifact          (every branch)
                    →  UPLOADS chart + perf-history.json to S3   (main only)
```

Two details worth knowing before changing this:

- **`pipeline_perf_chart.py` writes the history too**, it does not only read it — it merges fresh runs from the GitHub API and saves back. So the S3 upload must happen *after* the chart step, not straight after `collect_run_metrics.py`.
- **The uploads are `main`-gated on purpose.** Non-`main` runs still fetch and append locally so a PR's chart has full context, but they never publish — otherwise a PR-branch run would permanently enter the canonical series. The chart upload was previously ungated, so PR runs overwrote `latest/pipeline-performance.png`; fixed in #615.
- **The fetch fails closed.** A missing S3 object aborts the run rather than silently starting a fresh series, which would discard the accumulated trend without anyone noticing — the failure mode behind #584.

## What counts as a "check" per scanner

| Scanner | Check count | Finding count | Notes |
|---|---|---|---|
| **Checkov** | `passed + failed` | `failed` (split into `new` / `accepted` via `checkov_diff.py`) | Real count — both passes and fails emit check rows per resource. |
| **AWS Config** | `CompliantRuleCount + NonCompliantRuleCount` | `NonCompliantRuleCount` | Live via `aws configservice describe-compliance-by-config-rule`. Only fires on main + `ENABLE_AWS_CONFIG=true`. |
| **pip-audit** | packages audited | vulnerabilities found | Each package = one dependency check. |
| **Semgrep** | `len(results)` — **same as findings** | `len(results)` by severity | SARIF output does not emit a "rules-run × files" count. `checks` here is a lower bound; the actual work done is higher. Flagged in the JSON with a `checks_note`. |
| **TruffleHog** | `len(lines)` — **same as findings** | `len(lines)` | Default JSON output does not emit a "files scanned" count. Same lower-bound caveat as Semgrep. |
| **Trivy** | Not included | Not included | The CI runner image is built + scanned in `risk-sentinel/container-build-sign` (the local `build-runner.yml` scan was retired in #331), not per compliance run. Tracked there alongside the image publish. See gap note below. |

### The semgrep / trufflehog gap

For throughput-as-a-KPI, the under-count for these two is the single biggest caveat. The fix is to either (a) switch semgrep to `--metrics=on` + parse the stats output, or (b) post-process trufflehog with `--verbose` to capture its files-scanned line. Either is a small follow-up and would bump the "checks" denominator significantly. Tracked for Phase C if the trend panels prove valuable.

## Schema

Per-run entry in `pipeline-perf-history.json`:

```json
{
  "id": 12345678,
  "workflow": "FedRAMP 20x Compliance Validation",
  "timestamp": "2026-04-24T12:00:00Z",
  "duration_sec": 252,
  "duration_min": 4.2,
  "metrics": {
    "scanners": {
      "checkov":    {"passed": 451, "failed": 36, "checks": 487, "findings_failed": 36, "findings_new": 0, "findings_accepted": 36, "patterns": ["ecs","ec2","azure-vm","config"]},
      "aws_config": {"compliant": 125, "non_compliant": 14, "checks": 139, "findings": 14},
      "pip_audit":  {"packages_audited": 52, "vulnerabilities": 0, "checks": 52, "findings": 0},
      "semgrep":    {"high": 0, "medium": 0, "low": 2, "findings": 2, "checks": 2, "checks_note": "findings-only; SARIF does not emit rules-run count"},
      "trufflehog": {"findings": 0, "checks": 0, "checks_note": "findings-only; default JSON does not emit files-scanned count"}
    },
    "totals": {
      "checks": 680,
      "findings_failed": 52,
      "findings_new": 0,
      "findings_accepted": 36
    }
  }
}
```

### Backward compatibility

- Pre-#133 history entries have no `metrics` block. The chart script drops those from the throughput and findings panels while still plotting their duration in the existing three panels.
- The collector's history-merge step is idempotent and preserves any fields it doesn't know about.
- Duration (`duration_sec`, `duration_min`) is written by `pipeline_perf_chart.py` from the GitHub API, not by the collector. Metrics and duration can land on an entry in either order; the merge is a dict-update, not a replace.

### Throughput is derived, not stored

`checks_per_min = total_checks / (duration_sec / 60)` is computed by `pipeline_perf_chart.py` at render time from entries that have both `metrics.totals.checks` and `duration_sec`. Storing a derived metric per row would invite drift when either number is corrected; deriving at render time lets the chart always reflect the current understanding.

## Reading the chart

`pipeline-performance.png` (job summary / run artifact / `latest/` in S3) has 5 panels top-to-bottom:

1. **Individuals (X) chart — duration**: one point per run, with pre-optimization / post-optimization / containerized phase bands and per-phase UCL/LCL. This is the executive view of wall-clock.
2. **Moving Range (mR) chart — duration**: per-phase variability. Signals of instability show up here even when the X chart looks stable.
3. **By-workflow bar — before vs after**: average duration per workflow, baseline vs current. Summary view.
4. **Throughput XmR — checks/min** *(new, #133)*: same XmR treatment as duration but on the throughput metric. When scope grows (more patterns, more rules) but checks/min holds or climbs, we're getting more done per minute — that's the efficiency story.
5. **Findings over time — stacked area** *(new, #133)*: accepted risk (grey) stacked under new / unaccepted (red). Total findings across all scanners overlaid as a line. The ideal pattern: total volume trending flat or down with the red band staying thin near the bottom.

## Bootstrap period

Old runs (825 as of 2026-04-24) don't have metrics. Panels 4 and 5 start populating on the first post-#133 compliance run on main. Expect the throughput and findings panels to look sparse for the first week as the data accumulates; both stabilize within 20-30 runs, which the existing pipeline generates in roughly 2-3 days.

## Related

- #133 — tracking issue (checks-per-minute + findings-over-time)
- #153 — persistent perf-history file this work extends
- #97 / #131 — CI runner container (Trivy scan context)
- #132 — AWS Config 139 conformance-pack rules (the check count AWS Config contributes)
