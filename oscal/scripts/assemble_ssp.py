#!/usr/bin/env python3
"""
Assemble an OSCAL System Security Plan (SSP) from Component Definitions.

Reads all CDEFs in a directory, extracts implemented-requirements,
and composes them into a single SSP document referencing the
FedRAMP HIGH baseline resolved profile catalog.

Usage:
    python3 assemble_ssp.py \
        --cdef-dir AWS/CDEF/ECS/ \
        --extra-cdef-dir sparc-compliance/cdefs/ \
        --profile docs/FedRAMP_20x/NIST_SP-800-53_rev5_HIGH-baseline-resolved-profile_catalog.json \
        --system-name "SPARC ECS Fargate" \
        --output oscal/ssp/sparc-ecs-ssp.json
"""

import argparse
import json
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(__file__))
from org_config import (
    load_config,
    stable_uuid,
    get_org_party,
    get_parties,
    get_roles,
    get_system_info,
    maybe_write_oscal,
)


def load_cdefs(cdef_dir):
    """Load all CDEF JSON files from a directory."""
    cdefs = []
    for filename in sorted(os.listdir(cdef_dir)):
        if filename.endswith(".json") and filename != "component-definition-template.json":
            filepath = os.path.join(cdef_dir, filename)
            with open(filepath) as f:
                cdefs.append(json.load(f))
    return cdefs


def extract_components(cdefs):
    """Extract components and their implemented requirements from CDEFs."""
    components = []
    all_requirements = {}

    for cdef in cdefs:
        cdef_data = cdef.get("component-definition", {})
        for component in cdef_data.get("components", []):
            comp_entry = {
                "uuid": component["uuid"],
                "type": component.get("type", "service"),
                "title": component["title"],
                "description": component.get("description", ""),
            }
            components.append(comp_entry)

            for ctrl_impl in component.get("control-implementations", []):
                for req in ctrl_impl.get("implemented-requirements", []):
                    control_id = req["control-id"]
                    if control_id not in all_requirements:
                        all_requirements[control_id] = []
                    all_requirements[control_id].append({
                        "uuid": str(uuid.uuid4()),
                        "control-id": control_id,
                        "description": req.get("description", ""),
                        "remarks": req.get("remarks", ""),
                        "component-uuid": component["uuid"],
                        "component-title": component["title"],
                    })

    return components, all_requirements


def load_profile_controls(profile_path):
    """Extract control IDs and metadata from the resolved profile catalog."""
    with open(profile_path) as f:
        catalog = json.load(f)

    control_ids = set()
    control_meta = {}

    for group in catalog.get("catalog", {}).get("groups", []):
        family_id = group.get("id", "")
        family_title = group.get("title", "")

        for control in group.get("controls", []):
            cid = control["id"]
            control_ids.add(cid)
            control_meta[cid] = {
                "title": control.get("title", ""),
                "family_id": family_id,
                "family_title": family_title,
                "is_enhancement": False,
            }
            for enhancement in control.get("controls", []):
                eid = enhancement["id"]
                control_ids.add(eid)
                control_meta[eid] = {
                    "title": enhancement.get("title", ""),
                    "family_id": family_id,
                    "family_title": family_title,
                    "is_enhancement": True,
                    "parent": cid,
                }

    return control_ids, control_meta


# Likely responsibility for controls not addressed by infrastructure CDEFs
RESPONSIBILITY_HINTS = {
    "ac-1": "Policy", "at-1": "Policy", "au-1": "Policy",
    "ca-1": "Policy", "cm-1": "Policy", "cp-1": "Policy",
    "ia-1": "Policy", "ir-1": "Policy", "ma-1": "Policy",
    "mp-1": "Policy", "pe-1": "Policy", "pl-1": "Policy",
    "pm-1": "Policy", "ps-1": "Policy", "pt-1": "Policy",
    "ra-1": "Policy", "sa-1": "Policy", "sc-1": "Policy",
    "si-1": "Policy", "sr-1": "Policy",
    # Physical / environmental — CSP inherited
    "pe-2": "CSP Inherited", "pe-3": "CSP Inherited",
    "pe-4": "CSP Inherited", "pe-5": "CSP Inherited",
    "pe-6": "CSP Inherited", "pe-8": "CSP Inherited",
    "pe-9": "CSP Inherited", "pe-10": "CSP Inherited",
    "pe-11": "CSP Inherited", "pe-12": "CSP Inherited",
    "pe-13": "CSP Inherited", "pe-14": "CSP Inherited",
    "pe-15": "CSP Inherited", "pe-16": "CSP Inherited",
    "pe-17": "CSP Inherited", "pe-18": "CSP Inherited",
    # Personnel security — organizational
    "ps-1": "Policy", "ps-2": "Policy", "ps-3": "Policy",
    "ps-4": "Policy", "ps-5": "Policy", "ps-6": "Policy",
    "ps-7": "Policy", "ps-8": "Policy", "ps-9": "Policy",
    # Awareness and training — organizational
    "at-2": "Policy", "at-3": "Policy", "at-4": "Policy",
    # Planning — organizational
    "pl-2": "Policy", "pl-4": "Policy",
    # Program management — organizational
    "pm-2": "Policy", "pm-3": "Policy", "pm-4": "Policy",
    "pm-5": "Policy", "pm-6": "Policy", "pm-7": "Policy",
    "pm-8": "Policy", "pm-9": "Policy", "pm-10": "Policy",
    "pm-11": "Policy", "pm-12": "Policy", "pm-13": "Policy",
    "pm-14": "Policy", "pm-15": "Policy", "pm-16": "Policy",
    # Risk assessment — organizational
    "ra-2": "Policy", "ra-3": "Policy",
    # Supply chain — organizational
    "sr-2": "Policy", "sr-3": "Policy",
    # Maintenance — hybrid
    "ma-2": "CSP Inherited", "ma-3": "CSP Inherited",
    "ma-4": "Hybrid", "ma-5": "CSP Inherited",
    "ma-6": "CSP Inherited",
}


def get_responsibility(control_id):
    """Determine likely responsibility for a gap control."""
    base = control_id.split(".")[0] if "." in control_id else control_id
    # Check exact match first
    if control_id in RESPONSIBILITY_HINTS:
        return RESPONSIBILITY_HINTS[control_id]
    if base in RESPONSIBILITY_HINTS:
        return RESPONSIBILITY_HINTS[base]
    # Family-level heuristics
    family = base.rsplit("-", 1)[0] if "-" in base else base
    family_map = {
        "pe": "CSP Inherited",
        "ps": "Policy",
        "at": "Policy",
        "pl": "Policy",
        "pm": "Policy",
        "sr": "Policy",
    }
    if family in family_map:
        return family_map[family]
    return "IaC / Application"


def build_ssp(system_name, pattern, components, requirements, profile_controls, control_meta, profile_path, config):
    """Build the OSCAL SSP document.

    The document-root `uuid` and `metadata.last-modified` are intentionally
    omitted here. They are assigned by `maybe_write_oscal()` only when
    content has actually changed, per NIST document-UUID guidance.
    """
    sys_info = get_system_info(config)

    # Build control implementations with stable UUIDs
    implemented = []
    unimplemented = []

    for control_id in sorted(profile_controls):
        if control_id in requirements:
            # OSCAL requires statement-id to be unique within an implemented-requirement.
            # Multiple components implementing the same control statement must share
            # one statement entry with a by-components array, not emit one statement
            # per component.
            by_components = []
            seen_component_uuids = set()
            for req in requirements[control_id]:
                comp_uuid = req["component-uuid"]
                if comp_uuid in seen_component_uuids:
                    continue
                seen_component_uuids.add(comp_uuid)
                by_components.append({
                    "component-uuid": comp_uuid,
                    "uuid": stable_uuid(config, pattern, "bycomp", control_id, comp_uuid),
                    "description": req["description"],
                    "remarks": req.get("remarks", ""),
                })
            statements = [
                {
                    "statement-id": f"{control_id}_smt",
                    "uuid": stable_uuid(config, pattern, "stmt", control_id),
                    "by-components": by_components,
                }
            ]
            implemented.append({
                "uuid": stable_uuid(config, pattern, "impl", control_id),
                "control-id": control_id,
                "statements": statements,
            })
        else:
            unimplemented.append(control_id)

    ssp = {
        "system-security-plan": {
            "metadata": {
                "title": f"{system_name} System Security Plan",
                "version": "1.0.0",
                "oscal-version": "1.1.2",
                "roles": get_roles(config),
                "parties": get_parties(config),
            },
            "import-profile": {
                "href": os.path.basename(profile_path),
            },
            "system-characteristics": {
                "system-ids": [
                    {
                        "id": sys_info["uuid"],
                        "identifier-type": "https://ietf.org/rfc/rfc4122",
                    }
                ],
                "system-name": sys_info["name"],
                "description": sys_info.get("description") or (
                    f"SPARC compliance platform deployed via Terraform IaC. "
                    f"Auto-assembled from {len(components)} CDEFs."
                ),
                "security-sensitivity-level": sys_info["security_sensitivity_level"],
                "system-information": {
                    "information-types": [
                        {
                            "uuid": stable_uuid(config, "info-type", it.get("title", "")),
                            "title": it.get("title", ""),
                            "description": it.get("description", ""),
                            "confidentiality-impact": {"base": it.get("confidentiality", "high")},
                            "integrity-impact": {"base": it.get("integrity", "high")},
                            "availability-impact": {"base": it.get("availability", "high")},
                        }
                        for it in sys_info.get("information_types") or [
                            {"title": "Compliance Data", "description": "SAP, SAR, POAM, profiles",
                             "confidentiality": "high", "integrity": "high", "availability": "high"}
                        ]
                    ],
                },
                "security-impact-level": {
                    "security-objective-confidentiality": sys_info["security_sensitivity_level"],
                    "security-objective-integrity": sys_info["security_sensitivity_level"],
                    "security-objective-availability": sys_info["security_sensitivity_level"],
                },
                "status": {"state": sys_info["status"]},
                "authorization-boundary": {
                    "description": f"The {system_name} deployment boundary "
                    "encompasses all Terraform-managed infrastructure "
                    "components defined in the OSCAL CDEFs.",
                },
            },
            "system-implementation": {
                "users": [
                    {
                        "uuid": stable_uuid(config, "user", p.get("role_id", "")),
                        "title": p.get("title", ""),
                        "role-ids": [p.get("role_id", "")],
                    }
                    for p in config.get("parties", [
                        {"title": "System Administrator", "role_id": "system-admin"},
                        {"title": "Compliance Analyst", "role_id": "system-owner"},
                    ])
                ],
                "components": [
                    {
                        "uuid": c["uuid"],
                        "type": c["type"],
                        "title": c["title"],
                        "description": c["description"],
                        "status": {"state": "operational"},
                    }
                    for c in components
                ],
            },
            "control-implementation": {
                "description": "Control implementations assembled from "
                "OSCAL Component Definitions. Each control maps to "
                "one or more infrastructure components managed via "
                "Terraform IaC.",
                "implemented-requirements": implemented,
            },
        }
    }

    return ssp, unimplemented


def main():
    parser = argparse.ArgumentParser(description="Assemble OSCAL SSP from CDEFs")
    parser.add_argument("--cdef-dir", required=True, help="Directory containing CDEF JSON files")
    parser.add_argument("--profile", required=True, help="Path to resolved profile catalog JSON")
    parser.add_argument("--system-name", required=True, help="System name for the SSP")
    parser.add_argument("--extra-cdef-dir", default="", help="Additional CDEF directory (e.g. SPARC app CDEFs)")
    parser.add_argument("--inheritance-dir", default="oscal/inheritance",
                        help="Directory containing inheritance CDEFs (aws-inherited.json, etc.)")
    parser.add_argument("--output", required=True, help="Output SSP JSON file path")
    parser.add_argument("--config", default="organization_variables.yml", help="Organization config YAML")
    args = parser.parse_args()

    config = load_config(args.config)
    # Derive pattern from output filename (e.g. sparc-ecs-ssp.json -> ecs)
    pattern = os.path.basename(args.output).replace("sparc-", "").replace("-ssp.json", "")

    print(f"Loading CDEFs from {args.cdef_dir}...")
    cdefs = load_cdefs(args.cdef_dir)
    print(f"  Found {len(cdefs)} CDEF files")

    if args.extra_cdef_dir and os.path.isdir(args.extra_cdef_dir):
        print(f"Loading extra CDEFs from {args.extra_cdef_dir}...")
        extra = load_cdefs(args.extra_cdef_dir)
        print(f"  Found {len(extra)} extra CDEF files")
        cdefs.extend(extra)

    if args.inheritance_dir and os.path.isdir(args.inheritance_dir):
        print(f"Loading inheritance CDEFs from {args.inheritance_dir}...")
        inheritance = load_cdefs(args.inheritance_dir)
        print(f"  Found {len(inheritance)} inheritance CDEF files")
        cdefs.extend(inheritance)

    components, requirements = extract_components(cdefs)
    print(f"  Extracted {len(components)} components")
    print(f"  Extracted {len(requirements)} unique controls with implementations")

    print(f"Loading profile from {args.profile}...")
    profile_controls, control_meta = load_profile_controls(args.profile)
    print(f"  Found {len(profile_controls)} controls in HIGH baseline")

    print("Assembling SSP...")
    ssp, unimplemented = build_ssp(
        args.system_name, pattern, components, requirements, profile_controls, control_meta, args.profile, config
    )

    covered = len(requirements)
    total = len(profile_controls)
    coverage = (covered / total * 100) if total > 0 else 0

    print(f"  Controls covered: {covered}/{total} ({coverage:.1f}%)")
    print(f"  Controls not yet addressed: {len(unimplemented)}")

    marker_dir = os.environ.get("OSCAL_CHANGE_MARKERS")
    changed = maybe_write_oscal(args.output, ssp, "system-security-plan", marker_dir=marker_dir)
    if changed:
        print(f"SSP written to {args.output} (content changed — new document UUID minted)")
    else:
        print(f"SSP at {args.output} unchanged — preserved prior document UUID")

    if unimplemented:
        gap_file = args.output.replace(".json", "-gaps.md")
        with open(gap_file, "w") as f:
            f.write(f"# SSP Gap Report — {args.system_name}\n\n")
            f.write(f"**Baseline**: NIST SP 800-53 Rev 5 HIGH Impact\n")
            f.write(f"**Controls covered**: {covered}/{total} ({coverage:.1f}%)\n")
            f.write(f"**Controls not addressed**: {len(unimplemented)}\n\n")

            # Summary by responsibility
            resp_counts = {}
            for cid in unimplemented:
                resp = get_responsibility(cid)
                resp_counts[resp] = resp_counts.get(resp, 0) + 1

            f.write("## Summary by Responsibility\n\n")
            f.write("| Responsibility | Count | Action |\n")
            f.write("| --- | --- | --- |\n")
            for resp in sorted(resp_counts.keys()):
                action = {
                    "Policy": "Organizational policy documentation",
                    "CSP Inherited": "Document CSP inheritance (AWS/Azure)",
                    "Hybrid": "Shared between CSP and organization",
                    "IaC / Application": "Add CDEFs or SPARC app coverage",
                }.get(resp, "Review and assign")
                f.write(f"| {resp} | {resp_counts[resp]} | {action} |\n")
            f.write(f"| **Total** | **{len(unimplemented)}** | |\n\n")

            # Group by family
            families = {}
            for cid in sorted(unimplemented):
                meta = control_meta.get(cid, {})
                fam = meta.get("family_title", "Unknown")
                if fam not in families:
                    families[fam] = []
                families[fam].append(cid)

            f.write("## Gaps by Control Family\n\n")
            for fam_title in sorted(families.keys()):
                controls = families[fam_title]
                f.write(f"### {fam_title} ({len(controls)} controls)\n\n")
                f.write("| Control | Title | Responsibility |\n")
                f.write("| --- | --- | --- |\n")
                for cid in controls:
                    meta = control_meta.get(cid, {})
                    title = meta.get("title", "")
                    resp = get_responsibility(cid)
                    f.write(f"| {cid} | {title} | {resp} |\n")
                f.write("\n")

        print(f"Gap report written to {gap_file}")


if __name__ == "__main__":
    main()
