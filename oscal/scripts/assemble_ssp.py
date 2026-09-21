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
import re
import yaml
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(__file__))
from org_config import (
    load_config,
    stable_uuid,
    SPARC_PROPS_NS,
    get_parties,
    get_roles,
    get_system_info,
    maybe_write_oscal,
)


def load_cdefs(cdef_dir):
    """Load all CDEF JSON files from a directory.

    Each CDEF is tagged with `_source_name` — the filename stem after the
    `component-definition-` prefix — so inventory-map.yml can name a component
    as `iam` and have it resolve to that file's component UUID (#632).
    """
    cdefs = []
    for filename in sorted(os.listdir(cdef_dir)):
        if filename.endswith(".json") and filename != "component-definition-template.json":
            filepath = os.path.join(cdef_dir, filename)
            with open(filepath) as f:
                cdef = json.load(f)
            stem = filename[:-5]
            if stem.startswith("component-definition-"):
                stem = stem[len("component-definition-"):]
            cdef["_source_name"] = stem
            cdefs.append(cdef)
    return cdefs


def component_uuid_index(cdefs):
    """Map inventory-map component names -> component UUID.

    Two addressing forms, because a CDEF file may declare several components
    that are genuinely different capabilities (iam declares the general IAM
    surface plus evidence-emit, evidence-reader and the CI chain):

      `iam`                       -> the file's FIRST component
      `iam#evidence-emit-role`    -> that component by title slug

    The explicit form matters: mapping every IAM role to one component would say
    an evidence-emit identity and the CI execute role implement the same thing,
    which is exactly the conflation separate components exist to prevent.
    """
    index = {}
    for cdef in cdefs:
        name = cdef.get("_source_name")
        comps = cdef.get("component-definition", {}).get("components", [])
        if not name:
            continue
        if comps and name not in index:
            index[name] = comps[0]["uuid"]
        for comp in comps:
            slug = re.sub(r"[^a-z0-9]+", "-", comp["title"].lower()).strip("-")
            index[f"{name}#{slug}"] = comp["uuid"]
            # Also index by a short slug so the map can say `iam#evidence-emit-role`
            # rather than repeating the full title.
            for token in ("evidence-emit", "evidence-reader", "ci-trust-execute-chain"):
                if token in slug:
                    index[f"{name}#{token}-role" if not token.endswith("chain") else f"{name}#ci-chain-role"] = comp["uuid"]
    return index


def build_inventory_items(inventory, mapping, comp_index, config, pattern):
    """Render deployed resources as OSCAL system-implementation/inventory-items.

    The N:1 relationship is the point: many inventory items reference ONE
    component via implemented-components[].component-uuid. Sixteen evidence-emit
    roles with identical capability are sixteen items against one component, not
    sixteen component definitions. Capability, ports and protocols live in the
    CDEF; instance facts live here.
    """
    exclude = set(mapping.get("exclude_types", []))
    rules = mapping.get("mappings", [])
    items, unmapped, missing_component = [], [], set()

    for res in inventory.get("resources", []):
        if res["type"] in exclude:
            continue

        rule = None
        for candidate in rules:
            if candidate["type"] != res["type"]:
                continue
            pat = candidate.get("name_pattern")
            if pat and not (re.search(pat, res.get("tf_name", ""))
                            or re.search(pat, res["attributes"].get("name", ""))):
                continue
            rule = candidate
            break

        if rule is None:
            unmapped.append(f"{res['type']} ({res['identifier']})")
            continue

        comp_uuid = comp_index.get(rule["component"])
        if not comp_uuid:
            missing_component.add(rule["component"])
            continue

        # OSCAL constrains inventory-item props in the default namespace to an
        # enumerated vocabulary (asset-id, asset-type, label, uri, fqdn, ...).
        # Anything outside it must carry an explicit ns, or oscal-cli rejects the
        # name. So: standard vocabulary where it fits, SPARC_PROPS_NS for the
        # Terraform-specific facts that have no OSCAL equivalent.
        props = [
            {"name": "asset-id", "value": res["identifier"]},
            {"name": "asset-type", "value": res["type"]},
            {"name": "label", "value": rule["class"]},
        ]
        vocab = {
            "dns_name": "fqdn",
            "engine": "software-name",
            "engine_version": "software-version",
            "arn": "uri",
        }
        for key, val in sorted(res["attributes"].items()):
            text = str(val).strip()
            if key == "name" or not text:
                continue
            if key in vocab:
                props.append({"name": vocab[key], "value": text})
            elif key in ("id",):
                continue  # already carried as asset-id
            else:
                props.append({"ns": SPARC_PROPS_NS, "name": key.replace("_", "-"), "value": text})
        if res.get("tf_address"):
            props.append({"ns": SPARC_PROPS_NS, "name": "terraform-address",
                          "value": res["tf_address"]})

        item = {
            "uuid": stable_uuid(config, pattern, "inventory", res["identifier"]),
            "description": f"{rule['class']}: {res['identifier']}",
            "props": props,
            # OSCAL constrains each implemented-component to carry an asset-id
            # prop — the concrete identifier of the deployed asset realising the
            # component. Without it oscal-cli fails on cardinality, not schema.
            "implemented-components": [{
                "component-uuid": comp_uuid,
                "props": [{"name": "asset-id", "value": res["identifier"]}],
            }],
        }
        if rule.get("remarks"):
            item["remarks"] = " ".join(rule["remarks"].split())
        items.append(item)

    # Both of these are hard errors. A silently-dropped resource produces an
    # inventory that reads as complete and is not — the failure shape this whole
    # effort exists to remove.
    if unmapped:
        raise ValueError(
            f"{len(unmapped)} resource(s) match no rule in inventory-map.yml and are "
            f"not excluded: {unmapped[:5]}"
        )
    if missing_component:
        raise ValueError(
            f"inventory-map.yml names component(s) with no matching CDEF: "
            f"{sorted(missing_component)}"
        )
    return items


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


# Responsibility categories (S1192, #526) — reused across the hints table,
# the family-level map, and the description lookup.
_POLICY = "Policy"
_CSP_INHERITED = "CSP Inherited"

# Likely responsibility for controls not addressed by infrastructure CDEFs
RESPONSIBILITY_HINTS = {
    "ac-1": _POLICY, "at-1": _POLICY, "au-1": _POLICY,
    "ca-1": _POLICY, "cm-1": _POLICY, "cp-1": _POLICY,
    "ia-1": _POLICY, "ir-1": _POLICY, "ma-1": _POLICY,
    "mp-1": _POLICY, "pe-1": _POLICY, "pl-1": _POLICY,
    "pm-1": _POLICY, "pt-1": _POLICY,
    "ra-1": _POLICY, "sa-1": _POLICY, "sc-1": _POLICY,
    "si-1": _POLICY, "sr-1": _POLICY,
    # Physical / environmental — CSP inherited
    "pe-2": _CSP_INHERITED, "pe-3": _CSP_INHERITED,
    "pe-4": _CSP_INHERITED, "pe-5": _CSP_INHERITED,
    "pe-6": _CSP_INHERITED, "pe-8": _CSP_INHERITED,
    "pe-9": _CSP_INHERITED, "pe-10": _CSP_INHERITED,
    "pe-11": _CSP_INHERITED, "pe-12": _CSP_INHERITED,
    "pe-13": _CSP_INHERITED, "pe-14": _CSP_INHERITED,
    "pe-15": _CSP_INHERITED, "pe-16": _CSP_INHERITED,
    "pe-17": _CSP_INHERITED, "pe-18": _CSP_INHERITED,
    # Personnel security — organizational
    "ps-1": _POLICY, "ps-2": _POLICY, "ps-3": _POLICY,
    "ps-4": _POLICY, "ps-5": _POLICY, "ps-6": _POLICY,
    "ps-7": _POLICY, "ps-8": _POLICY, "ps-9": _POLICY,
    # Awareness and training — organizational
    "at-2": _POLICY, "at-3": _POLICY, "at-4": _POLICY,
    # Planning — organizational
    "pl-2": _POLICY, "pl-4": _POLICY,
    # Program management — organizational
    "pm-2": _POLICY, "pm-3": _POLICY, "pm-4": _POLICY,
    "pm-5": _POLICY, "pm-6": _POLICY, "pm-7": _POLICY,
    "pm-8": _POLICY, "pm-9": _POLICY, "pm-10": _POLICY,
    "pm-11": _POLICY, "pm-12": _POLICY, "pm-13": _POLICY,
    "pm-14": _POLICY, "pm-15": _POLICY, "pm-16": _POLICY,
    # Risk assessment — organizational
    "ra-2": _POLICY, "ra-3": _POLICY,
    # Supply chain — organizational
    "sr-2": _POLICY, "sr-3": _POLICY,
    # Maintenance — hybrid
    "ma-2": _CSP_INHERITED, "ma-3": _CSP_INHERITED,
    "ma-4": "Hybrid", "ma-5": _CSP_INHERITED,
    "ma-6": _CSP_INHERITED,
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
        "pe": _CSP_INHERITED,
        "ps": _POLICY,
        "at": _POLICY,
        "pl": _POLICY,
        "pm": _POLICY,
        "sr": _POLICY,
    }
    if family in family_map:
        return family_map[family]
    return "IaC / Application"


# Custom namespace for boundary props, matching the sparc-validate namespace convention.
BOUNDARY_NS = "https://github.com/risk-sentinel/sparc-validate/v1"


def load_boundary_protection(path):
    """Load the boundary-protection block from a Phase B JSON file, or {}."""
    if not path or not os.path.exists(path):
        return {}
    with open(path) as f:
        data = json.load(f)
    return data.get("boundary-protection", {}) or {}


def apply_boundary_protection(components, boundary, config):  # NOSONAR
    # NOSONAR S3516/S3776 (#526): the mutate-in-place-AND-return pattern is
    # intentional — the return gives callers/tests a reference to the same
    # mutated list (test_assemble_ssp relies on it), so the "invariant return"
    # is by design; the boundary-matching nesting is inherent and covered by tests.
    """Attach native OSCAL protocols[] + boundary props[] to matching components.

    Each boundary entry's `title-match` is matched (case-insensitive substring)
    against the component title (titles come from CDEFs, e.g. "AWS RDS
    PostgreSQL"). TLS and IAM data-access grants become custom-ns props. The
    components list is mutated in place and returned. No-op when boundary is
    empty, so the SSP is unchanged for patterns without a boundary file.
    """
    entries = (boundary or {}).get("components", [])
    if not entries:
        return components
    for comp in components:
        title_lower = comp.get("title", "").lower()
        protocols = []
        props = []
        for entry in entries:
            tm = entry.get("title-match", "")
            if not tm or tm.lower() not in title_lower:
                continue
            for p in entry.get("protocols", []):
                protocols.append({
                    "uuid": stable_uuid(config, "protocol", comp.get("title", ""),
                                        p.get("name", ""), str(p.get("start", ""))),
                    "name": p.get("name", ""),
                    "port-ranges": [{
                        "start": p.get("start"),
                        "end": p.get("end", p.get("start")),
                        "transport": p.get("transport", "TCP"),
                    }],
                })
                if p.get("tls"):
                    props.append({"ns": BOUNDARY_NS, "name": "transit-encryption",
                                  "value": f"{p.get('name', '')}:{p.get('start')} {p['tls']}"})
            for g in entry.get("access-grants", []):
                props.append({"ns": BOUNDARY_NS, "name": "data-access",
                              "value": f"{g.get('action', '')} on {g.get('arn', '*')}"})
        if protocols:
            comp["protocols"] = protocols
        if props:
            comp["props"] = props
    return components


def build_ssp(system_name, pattern, components, requirements, profile_controls, control_meta, profile_path, config, boundary=None, inventory_items=None):  # NOSONAR S1172 — control_meta kept for signature completeness alongside profile_controls (the metadata pair is passed together by convention) (#526)
    """Build the OSCAL SSP document.

    The document-root `uuid` and `metadata.last-modified` are intentionally
    omitted here. They are assigned by `maybe_write_oscal()` only when
    content has actually changed, per NIST document-UUID guidance.
    """
    sys_info = get_system_info(config)

    # Build the system-implementation components, then augment matching ones
    # with native OSCAL protocols[]/port-ranges[] + boundary props[] (Phase B).
    system_components = [
        {
            "uuid": c["uuid"],
            "type": c["type"],
            "title": c["title"],
            "description": c["description"],
            "status": {"state": "operational"},
        }
        for c in components
    ]
    apply_boundary_protection(system_components, boundary, config)

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
                "oscal-version": "1.2.1",
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
                "components": system_components,
                # #632 — what is actually deployed. Each item references the
                # component it realises; many items may share one component.
                **({"inventory-items": inventory_items} if inventory_items else {}),
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


def main():  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
    parser = argparse.ArgumentParser(description="Assemble OSCAL SSP from CDEFs")
    parser.add_argument("--cdef-dir", required=True, help="Directory containing CDEF JSON files")
    parser.add_argument("--profile", required=True, help="Path to resolved profile catalog JSON")
    parser.add_argument("--inventory", help="Path to extract_inventory.py output (#632). Omitted = no inventory-items.")
    parser.add_argument("--inventory-map", default="oscal/inventory-map.yml", help="Resource-type -> CDEF component mapping (#632)")
    parser.add_argument("--system-name", required=True, help="System name for the SSP")
    parser.add_argument("--extra-cdef-dir", default="", help="Additional CDEF directory (e.g. SPARC app CDEFs)")
    parser.add_argument("--inheritance-dir", default="oscal/inheritance",
                        help="Directory containing inheritance CDEFs (aws-inherited.json, etc.)")
    parser.add_argument("--output", required=True, help="Output SSP JSON file path")
    parser.add_argument("--boundary-json", default="",
                        help="Optional boundary-protection.json (Phase B / #347) whose "
                             "protocols/TLS/IAM data is merged into matching components")
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

    boundary = load_boundary_protection(args.boundary_json)
    if boundary:
        n = len(boundary.get("components", []))
        print(f"  Loaded boundary-protection data ({n} components) from {args.boundary_json}")
    elif args.boundary_json:
        print(f"  No boundary-protection data at {args.boundary_json} (skipping)")

    # #632 — deployed-resource inventory. Optional so the generator still runs
    # where state is unavailable (public template, local dry runs); when supplied,
    # an unmapped resource is a hard error rather than a silent omission.
    inventory_items = None
    if args.inventory:
        with open(args.inventory) as handle:
            inventory = json.load(handle)
        with open(args.inventory_map) as handle:
            inv_map = yaml.safe_load(handle)
        inventory_items = build_inventory_items(
            inventory, inv_map, component_uuid_index(cdefs), config, pattern
        )
        print(f"  Inventory: {len(inventory_items)} items from "
              f"{inventory.get('resource_count', 0)} resources "
              f"(deployed_sha={inventory.get('deployed_sha', '') or 'unset'})")

    print("Assembling SSP...")
    ssp, unimplemented = build_ssp(
        args.system_name, pattern, components, requirements, profile_controls, control_meta, args.profile, config,
        boundary=boundary, inventory_items=inventory_items,
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
            f.write("**Baseline**: NIST SP 800-53 Rev 5 HIGH Impact\n")
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
                    _POLICY: "Organizational policy documentation",
                    _CSP_INHERITED: "Document CSP inheritance (AWS/Azure)",
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
