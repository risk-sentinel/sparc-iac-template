#!/usr/bin/env python3
"""
Generate an OSCAL POA&M from Checkov accepted risks.

Reads a checkov JSON results file, extracts failed checks,
and generates an OSCAL plan-of-action-and-milestones document
with each finding as a POA&M item.

Usage:
    python3 generate_poam.py \
        --checkov-results checkov-results/ecs_1774010089_results.json \
        --system-name "SPARC ECS Fargate" \
        --output oscal/poam/sparc-ecs-poam.json
"""

import argparse
import json
import os
import sys

import yaml

from org_config import load_config, stable_uuid, maybe_write_oscal, now_iso

# Same mapping as checkov_to_oscal.py
CHECKOV_TO_NIST = {
    "CKV_AWS_149": "sc-28", "CKV_AWS_158": "sc-28",
    "CKV_AWS_136": "sc-28", "CKV_AWS_191": "sc-28",
    "CKV_AWS_354": "sc-28", "CKV_AWS_189": "sc-28",
    "CKV_AWS_130": "ac-4", "CKV_AWS_260": "ac-3",
    "CKV_AWS_382": "ac-4", "CKV_AWS_157": "cp-9",
    "CKV_AWS_91": "sc-8", "CKV2_AWS_5": "sc-7",
    "CKV2_AWS_11": "sc-7", "CKV2_AWS_12": "sc-7",
    "CKV2_AWS_28": "sc-7", "CKV2_AWS_57": "ia-5",
    "CKV2_AWS_50": "cp-9", "CKV2_AWS_60": "cp-9",
    "CKV2_AWS_30": "au-2", "CKV_AWS_144": "cp-9",
    "CKV_AWS_18": "au-2", "CKV2_AWS_61": "cm-2",
    "CKV2_AWS_62": "si-4",
    "CKV_AZURE_109": "sc-7", "CKV_AZURE_120": "sc-7",
    "CKV_AZURE_136": "cp-9", "CKV_AZURE_160": "ac-3",
    "CKV_AZURE_182": "sc-20", "CKV_AZURE_183": "sc-20",
    "CKV_AZURE_189": "sc-7", "CKV_AZURE_206": "cp-9",
    "CKV_AZURE_218": "sc-8", "CKV_AZURE_230": "cp-9",
}


def load_accepted_rationales(baseline_path):
    """Load accepted risk rationales from checkov-baseline.yml."""
    with open(baseline_path) as f:
        data = yaml.safe_load(f)

    return {
        entry["check_id"]: entry["rationale"]
        for entry in data.get("findings", [])
        if entry.get("disposition") == "accepted"
    }


def load_checkov_results(filepath):
    with open(filepath) as f:
        data = json.load(f)
    return data if isinstance(data, list) else [data]


def build_poam(results, system_name, config, accepted_rationales):
    """Build the OSCAL POA&M document.

    The document-root `uuid` and `metadata.last-modified` are omitted — they
    are assigned by `maybe_write_oscal()` only on actual content change, per
    NIST document-UUID guidance.
    """
    now = now_iso()

    # OSCAL 1.1.2: observations and risks are root-level arrays on the POAM.
    # poam-items reference them via {observation-uuid} / {risk-uuid} only —
    # no description, status, or other fields are permitted inline.
    observations = []
    risks = []
    poam_items = []

    for result_set in results:
        for check in result_set.get("results", {}).get("failed_checks", []):
            check_id = check["check_id"]
            control_id = CHECKOV_TO_NIST.get(check_id, "cm-2")
            resource = check.get("resource", "unknown")
            rationale = accepted_rationales.get(
                check_id,
                "Under review — see checkov-baseline.yml",
            )

            obs_uuid = stable_uuid(config, "poam-obs", check_id, resource)
            risk_uuid = stable_uuid(config, "poam-risk", check_id, resource)

            observations.append({
                "uuid": obs_uuid,
                "description": rationale,
                "methods": ["TEST"],
                "types": ["finding"],
                "collected": now,
            })

            risks.append({
                "uuid": risk_uuid,
                "title": f"{check_id}: {resource}",
                "description": f"Checkov finding {check_id} on resource {resource}. "
                f"Mapped to NIST 800-53 control {control_id}.",
                "statement": rationale,
                "status": "deviation-approved",
            })

            poam_items.append({
                "uuid": stable_uuid(config, "poam-item", check_id, resource),
                "title": f"{check_id}: {resource}",
                "description": f"Checkov finding {check_id} on resource {resource}. "
                f"Mapped to NIST 800-53 control {control_id}.",
                "related-observations": [
                    {"observation-uuid": obs_uuid}
                ],
                "related-risks": [
                    {"risk-uuid": risk_uuid}
                ],
                "remarks": f"Control: {control_id}. "
                f"Risk acceptance documented in "
                f"checkov-baseline.yml",
            })

    poam = {
        "plan-of-action-and-milestones": {
            "metadata": {
                "title": f"{system_name} Plan of Action and Milestones",
                "version": "1.0.0",
                "oscal-version": "1.1.2",
            },
            "import-ssp": {
                "href": "#system-security-plan",
            },
            "observations": observations,
            "risks": risks,
            "poam-items": poam_items,
        }
    }

    return poam


def main():
    parser = argparse.ArgumentParser(description="Generate OSCAL POA&M from Checkov")
    parser.add_argument("--checkov-results", required=True)
    parser.add_argument("--system-name", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--baseline", default="checkov-baseline.yml",
                        help="Path to checkov-baseline.yml for accepted rationales")
    parser.add_argument("--config", default="organization_variables.yml", help="Organization config YAML")
    args = parser.parse_args()

    config = load_config(args.config)

    print(f"Loading accepted rationales from {args.baseline}...")
    accepted_rationales = load_accepted_rationales(args.baseline)
    print(f"  Loaded {len(accepted_rationales)} accepted rationales")

    print(f"Loading checkov results from {args.checkov_results}...")
    results = load_checkov_results(args.checkov_results)

    print("Generating POA&M...")
    poam = build_poam(results, args.system_name, config, accepted_rationales)

    items = poam["plan-of-action-and-milestones"]["poam-items"]
    print(f"  POA&M items: {len(items)}")

    marker_dir = os.environ.get("OSCAL_CHANGE_MARKERS")
    changed = maybe_write_oscal(args.output, poam, "plan-of-action-and-milestones", marker_dir=marker_dir)
    if changed:
        print(f"POA&M written to {args.output} (content changed — new document UUID minted)")
    else:
        print(f"POA&M at {args.output} unchanged — preserved prior document UUID")


if __name__ == "__main__":
    main()
