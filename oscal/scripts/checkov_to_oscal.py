#!/usr/bin/env python3
"""
Convert Checkov JSON results to OSCAL Assessment Results (SAR).

Maps checkov findings to NIST 800-53 controls and generates
a valid OSCAL assessment-results document.

Usage:
    python3 checkov_to_oscal.py \
        --checkov-results checkov-results/ecs_1774009451_results.json \
        --system-name "SPARC ECS Fargate" \
        --output oscal/sar/sparc-ecs-sar.json
"""

import argparse
import json
import os
import sys

from org_config import (
    load_config,
    stable_uuid,
    get_tool_party,
    maybe_write_oscal,
    now_iso,
)

# Map checkov check IDs to NIST 800-53 controls
CHECKOV_TO_NIST = {
    # Encryption at rest
    "CKV_AWS_149": "sc-28", "CKV_AWS_158": "sc-28",
    "CKV_AWS_136": "sc-28", "CKV_AWS_191": "sc-28",
    "CKV_AWS_354": "sc-28", "CKV_AWS_189": "sc-28",
    "CKV_AWS_26": "sc-28",
    # Encryption in transit
    "CKV_AWS_91": "sc-8", "CKV_AWS_31": "sc-8",
    # Access control
    "CKV_AWS_260": "ac-3", "CKV_AWS_382": "ac-4",
    "CKV_AWS_130": "ac-4", "CKV_AWS_356": "ac-6",
    "CKV_AWS_111": "ac-6",
    # Boundary protection
    "CKV2_AWS_5": "sc-7", "CKV2_AWS_12": "sc-7",
    "CKV2_AWS_11": "sc-7", "CKV2_AWS_28": "sc-7",
    # Configuration management
    "CKV_AWS_65": "cm-2", "CKV_AWS_338": "au-2",
    "CKV_AWS_336": "cm-7", "CKV_AWS_131": "sc-7",
    "CKV_AWS_150": "cp-9", "CKV_AWS_135": "cm-2",
    # Monitoring
    "CKV_AWS_118": "au-2", "CKV_AWS_129": "au-2",
    "CKV_AWS_353": "au-2",
    # Authentication
    "CKV_AWS_161": "ia-2", "CKV_AWS_226": "si-2",
    "CKV_AWS_293": "cp-9",
    # Secrets
    "CKV2_AWS_57": "ia-5",
    # Availability
    "CKV_AWS_157": "cp-9", "CKV2_AWS_50": "cp-9",
    "CKV2_AWS_60": "cp-9",
    # S3
    "CKV_AWS_144": "cp-9", "CKV_AWS_18": "au-2",
    "CKV2_AWS_61": "cm-2", "CKV2_AWS_62": "si-4",
    # RDS
    "CKV2_AWS_30": "au-2",
    # Azure mappings
    "CKV_AZURE_109": "sc-7", "CKV_AZURE_114": "ia-5",
    "CKV_AZURE_120": "sc-7", "CKV_AZURE_136": "cp-9",
    "CKV_AZURE_160": "ac-3", "CKV_AZURE_182": "sc-20",
    "CKV_AZURE_189": "sc-7", "CKV_AZURE_206": "cp-9",
    "CKV_AZURE_218": "sc-8", "CKV_AZURE_230": "cp-9",
    "CKV_AZURE_251": "sc-28", "CKV_AZURE_33": "au-2",
    "CKV_AZURE_41": "ia-5", "CKV_AZURE_50": "cm-7",
    "CKV_AZURE_59": "ac-3", "CKV_AZURE_93": "sc-28",
}


def load_checkov_results(filepath):
    """Load checkov JSON results (handles single or array format)."""
    with open(filepath) as f:
        data = json.load(f)
    return data if isinstance(data, list) else [data]


def build_assessment_results(results, system_name, config):
    """Convert checkov results to OSCAL Assessment Results.

    Observation, finding, and result UUIDs are derived deterministically from
    (check_id, resource) so that rerunning the same scan produces the same
    UUIDs — which in turn lets `maybe_write_oscal()` detect identical content
    and avoid minting a fresh document UUID for a no-op scan.

    The document-root `uuid` and `metadata.last-modified` are left unset here
    and assigned by `maybe_write_oscal()` only on actual content change.
    Timestamp fields (`collected`, `start`, `end`) are populated with `now`
    but excluded from the content hash.
    """
    now = now_iso()

    findings = []
    observations = []
    total_passed = 0
    total_failed = 0

    for result_set in results:
        summary = result_set.get("summary", {})
        total_passed += summary.get("passed", 0)
        total_failed += summary.get("failed", 0)

        for check in result_set.get("results", {}).get("passed_checks", []):
            check_id = check["check_id"]
            resource = check.get("resource", "unknown")
            control_id = CHECKOV_TO_NIST.get(check_id, "cm-2")
            obs_uuid = stable_uuid(config, "sar-obs", "checkov", check_id, resource)

            observations.append({
                "uuid": obs_uuid,
                "title": f"PASS: {check_id}",
                "description": check_id,
                "methods": ["AUTOMATED"],
                "collected": now,
                "remarks": f"Resource: {resource}",
            })

            findings.append({
                "uuid": stable_uuid(config, "sar-finding", "checkov", check_id, resource),
                "title": check_id,
                "description": f"Passed check on {resource}",
                "target": {
                    "type": "objective-id",
                    "target-id": control_id,
                    "status": {"state": "satisfied"},
                },
                "related-observations": [{"observation-uuid": obs_uuid}],
            })

        for check in result_set.get("results", {}).get("failed_checks", []):
            check_id = check["check_id"]
            resource = check.get("resource", "unknown")
            control_id = CHECKOV_TO_NIST.get(check_id, "cm-2")
            obs_uuid = stable_uuid(config, "sar-obs", "checkov", check_id, resource)

            observations.append({
                "uuid": obs_uuid,
                "title": f"FAIL: {check_id}",
                "description": check_id,
                "methods": ["AUTOMATED"],
                "collected": now,
                "remarks": f"Resource: {resource}. "
                f"File: {check.get('file_path', 'unknown')}",
            })

            findings.append({
                "uuid": stable_uuid(config, "sar-finding", "checkov", check_id, resource),
                "title": check_id,
                "description": f"Failed check on {resource}",
                "target": {
                    "type": "objective-id",
                    "target-id": control_id,
                    "status": {"state": "not-satisfied"},
                },
                "related-observations": [{"observation-uuid": obs_uuid}],
            })

    total = total_passed + total_failed
    pass_rate_txt = f"{(total_passed / total * 100):.1f}%" if total else "n/a"

    sar = {
        "assessment-results": {
            "metadata": {
                "title": f"{system_name} Assessment Results",
                "version": "1.0.0",
                "oscal-version": "1.1.2",
                "roles": [
                    {"id": "assessor", "title": "Automated Assessor (Checkov)"}
                ],
                "parties": [
                    get_tool_party(config, "Checkov")
                ],
            },
            "import-ap": {
                "href": "#assessment-plan",
                "remarks": "Automated assessment via Checkov static analysis",
            },
            "results": [
                {
                    "uuid": stable_uuid(config, system_name, "checkov-result"),
                    "title": "Checkov Scan",
                    "description": f"Automated Terraform configuration scan. "
                    f"Passed: {total_passed}, Failed: {total_failed}, "
                    f"Pass rate: {pass_rate_txt}",
                    "start": now,
                    "end": now,
                    "reviewed-controls": {
                        "control-selections": [
                            {
                                "description": "All controls in the imported assessment plan's profile are in scope for this automated scan.",
                                "include-all": {},
                            }
                        ]
                    },
                    "observations": observations,
                    "findings": findings,
                }
            ],
        }
    }

    return sar, total_passed, total_failed


def main():
    parser = argparse.ArgumentParser(
        description="Convert Checkov results to OSCAL Assessment Results"
    )
    parser.add_argument("--checkov-results", required=True, help="Checkov JSON results file")
    parser.add_argument("--system-name", required=True, help="System name")
    parser.add_argument("--output", required=True, help="Output OSCAL SAR JSON file")
    parser.add_argument("--config", default="organization_variables.yml", help="Organization config YAML")
    args = parser.parse_args()

    config = load_config(args.config)

    print(f"Loading checkov results from {args.checkov_results}...")
    results = load_checkov_results(args.checkov_results)

    print("Converting to OSCAL Assessment Results...")
    sar, passed, failed = build_assessment_results(results, args.system_name, config)

    print(f"  Passed: {passed}, Failed: {failed}")
    print(f"  Findings: {len(sar['assessment-results']['results'][0]['findings'])}")

    marker_dir = os.environ.get("OSCAL_CHANGE_MARKERS")
    changed = maybe_write_oscal(args.output, sar, "assessment-results", marker_dir=marker_dir)
    if changed:
        print(f"Assessment Results written to {args.output} (content changed — new document UUID minted)")
    else:
        print(f"Assessment Results at {args.output} unchanged — preserved prior document UUID")


if __name__ == "__main__":
    main()
