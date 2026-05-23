#!/usr/bin/env python3
"""
Convert MITRE SAF HDF (Heimdall Data Format) files to OSCAL Assessment Results.

Reads HDF JSON files produced by SAF CLI from SPARC's security scanning
pipeline (Brakeman, CodeQL, Trivy, Gitleaks, etc.) and converts them to
OSCAL assessment-results documents.

Inheritance semantics (#187):
    HDF controls produced by sparc-validate may carry these tags:

        tag implementation_status:    'inherited' | 'implemented' | 'alternative'
                                      | 'not-applicable' | 'planned'
        tag inherited_from:           'aws-shared-responsibility'  # only when inherited
        tag attestation_references:   ['AWS SOC 2 Type II', ...]   # only when inherited

    Mapping into OSCAL 1.1.2:
      - 'inherited' is NOT a valid implementation-status.state enum. To express
        inheritance correctly we populate
        results[].local-definitions.components[].control-implementations[]
        .implemented-requirements[].statements[].by-components[].inherited[],
        with the AWS attestation references resolved against
        back-matter.resources[]. The aws-cloud-provider component is defined
        once in local-definitions.components[].
      - Other implementation_status values map to a custom prop on the finding
        (ns:    https://github.com/risk-sentinel/sparc-validate/v1
         name:  implementation-status
         value: implemented | alternative | not-applicable | planned).
      - Tag absent: existing behaviour, no change.

Usage:
    python3 hdf_to_oscal.py \
        --hdf-dir /path/to/hdf/ \
        --system-name "SPARC Application" \
        --output-dir oscal/sar/application/
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

# --- Inheritance constants (#187) ----------------------------------------

# Stable OSCAL namespace identifier — NOT a fetched URL. Retained verbatim
# through the risk-sentinel → risk-sentinel org migration (#204) because
# downstream OSCAL consumers key on the namespace string.
SPARC_VALIDATE_PROP_NS = "https://github.com/risk-sentinel/sparc-validate/v1"

# OSCAL implementation-status.state legal enum (1.1.2). 'inherited' is NOT
# in this list — see module docstring for how inheritance is modelled.
LEGAL_IMPLEMENTATION_STATUS = {
    "implemented",
    "partial",
    "planned",
    "alternative",
    "not-applicable",
}

# Default attestation catalog. Issue #187 lists SOC 2 Type II + FedRAMP
# Moderate + FedRAMP High + ISO 27001. Any value referenced via
# attestation_references that isn't in this table is still emitted but with
# no description — sparc-validate can extend the catalog without code
# changes here.
AWS_ATTESTATION_CATALOG = {
    "AWS SOC 2 Type II": {
        "title": "AWS SOC 2 Type II Report",
        "description": "AWS SOC 2 Type II report covering security, availability, processing integrity, confidentiality, and privacy. Available via AWS Artifact.",
        "url": "https://aws.amazon.com/compliance/soc-faqs/",
    },
    "AWS FedRAMP Moderate": {
        "title": "AWS FedRAMP Moderate Authorization",
        "description": "AWS FedRAMP Moderate authorization package. Available via AWS Artifact for federal customers.",
        "url": "https://aws.amazon.com/compliance/fedramp/",
    },
    "AWS FedRAMP High": {
        "title": "AWS FedRAMP High Authorization",
        "description": "AWS FedRAMP High authorization package (GovCloud + Commercial). Available via AWS Artifact for federal customers.",
        "url": "https://aws.amazon.com/compliance/fedramp/",
    },
    "AWS ISO 27001": {
        "title": "AWS ISO/IEC 27001 Certification",
        "description": "AWS ISO/IEC 27001:2013 certification covering its information security management system. Available via AWS Artifact.",
        "url": "https://aws.amazon.com/compliance/iso-27001-faqs/",
    },
}

AWS_PROVIDER_COMPONENT_TITLE = "AWS (Cloud Service Provider)"
AWS_PROVIDER_COMPONENT_DESCRIPTION = (
    "Amazon Web Services as the cloud service provider under the shared-"
    "responsibility model. Inherited control responsibilities (physical "
    "security, hypervisor isolation, environmental controls, etc.) are "
    "satisfied by AWS and evidenced by their independently-audited "
    "attestations referenced in back-matter."
)


def _read_implementation_status(control):
    """Pull (status, inherited_from, attestation_refs) from an HDF control's tags.

    Returns a tuple:
        (status, inherited_from, attestation_refs)
    where:
        status            : str | None — one of LEGAL_IMPLEMENTATION_STATUS,
                            or the literal "inherited", or None when absent.
        inherited_from    : str | None — populated only when status == 'inherited'.
        attestation_refs  : list[str] — empty list if absent.

    Tag-absent and malformed-tag cases return (None, None, []), preserving
    pre-#187 behaviour for HDFs that don't carry the new tags.
    """
    tags = control.get("tags") or {}
    if not isinstance(tags, dict):
        return None, None, []

    status_raw = tags.get("implementation_status")
    if not isinstance(status_raw, str):
        return None, None, []
    status = status_raw.strip().lower()
    if status not in LEGAL_IMPLEMENTATION_STATUS and status != "inherited":
        # Unknown value — ignore rather than emit invalid OSCAL.
        return None, None, []

    inherited_from = None
    attestation_refs = []
    if status == "inherited":
        inh = tags.get("inherited_from")
        if isinstance(inh, str):
            inherited_from = inh.strip()
        refs = tags.get("attestation_references")
        if isinstance(refs, list):
            attestation_refs = [r for r in refs if isinstance(r, str) and r.strip()]

    return status, inherited_from, attestation_refs


def _aws_provider_component(config):
    """Return the OSCAL component dict for AWS as cloud-service provider.

    UUID is stable across reruns so document deltas only fire on real changes.
    """
    return {
        "uuid": stable_uuid(config, "aws-cloud-provider", "component"),
        "type": "service",
        "title": AWS_PROVIDER_COMPONENT_TITLE,
        "description": AWS_PROVIDER_COMPONENT_DESCRIPTION,
        "props": [
            {
                "name": "implementation-point",
                "value": "external",
            }
        ],
    }


def _aws_attestation_resources(config, attestation_names):
    """Build back-matter resource entries for the cited AWS attestations.

    `attestation_names` is the union of all attestation_references seen
    across all inherited controls in the SAR. Returns a list of OSCAL
    resource dicts with stable UUIDs. Names not in AWS_ATTESTATION_CATALOG
    are still emitted but with title-only metadata (no description / URL).

    Returns an empty list if `attestation_names` is empty so we don't add
    a back-matter section unless inheritance is actually claimed.
    """
    resources = []
    for name in sorted(set(attestation_names)):
        catalog_entry = AWS_ATTESTATION_CATALOG.get(name, {})
        resource = {
            "uuid": stable_uuid(config, "aws-attestation", name),
            "title": catalog_entry.get("title", name),
            "props": [
                {
                    "name": "type",
                    "value": "attestation",
                },
                {
                    "ns": SPARC_VALIDATE_PROP_NS,
                    "name": "attestation-name",
                    "value": name,
                },
            ],
        }
        if "description" in catalog_entry:
            resource["description"] = catalog_entry["description"]
        if "url" in catalog_entry:
            resource["rlinks"] = [{"href": catalog_entry["url"]}]
        resources.append(resource)
    return resources


def _attestation_uuid(config, name):
    """Stable UUID lookup for an attestation by name (matches _aws_attestation_resources)."""
    return stable_uuid(config, "aws-attestation", name)

# Map HDF profile names / tool names to NIST 800-53 control families
TOOL_CONTROL_MAPPING = {
    "brakeman": {
        "default": "si-10",
        "SQL Injection": "si-10",
        "Cross-Site Scripting": "si-10",
        "Mass Assignment": "ac-3",
        "Command Injection": "si-10",
        "File Access": "ac-3",
        "Authentication": "ia-2",
        "Session": "ac-12",
    },
    "codeql": {
        "default": "si-3",
        "sql-injection": "si-10",
        "xss": "si-10",
        "path-injection": "ac-3",
        "code-injection": "si-3",
    },
    "gitleaks": {
        "default": "ia-5",
    },
    "trivy-fs": {
        "default": "si-2",
        "CRITICAL": "si-2",
        "HIGH": "si-2",
        "MEDIUM": "si-2",
    },
    "trivy-container": {
        "default": "si-2",
        "CRITICAL": "si-2",
        "HIGH": "si-2",
    },
    "trivy-fs-sbom": {
        "default": "cm-8",
    },
    "trivy-container-sbom": {
        "default": "cm-8",
    },
    "sbom-ruby": {
        "default": "cm-8",
    },
    # --- sparc-iac pipeline tools (consumed via SAF CLI sarif2hdf / dedicated converters) ---
    "semgrep": {
        "default": "si-10",         # Input validation
        "injection": "si-10",
        "security": "ac-3",         # Access enforcement
        "path-traversal": "ac-3",
    },
    "trufflehog": {
        "default": "ia-5",          # Authenticator management (leaked creds)
    },
    "pip-audit": {
        "default": "si-2",          # Flaw remediation (known vulns)
    },
    "checkov": {
        "default": "cm-6",          # Configuration settings
        "networking": "sc-7",       # Boundary protection
        "encryption": "sc-28",      # Data at rest
        "iam": "ac-3",              # Access enforcement
        "logging": "au-2",          # Audit events
    },
    "aws-config": {
        "default": "cm-6",          # Configuration management
        "encrypted": "sc-28",       # Protection of information at rest
        "iam": "ac-6",              # Least privilege
        "mfa": "ia-2",              # Identification and authentication
        "logging": "au-2",          # Audit events
        "flow-log": "au-2",         # Audit events (VPC)
        "ssh": "sc-7",              # Boundary protection
        "ssl": "sc-8",              # Transmission confidentiality
        "multi-az": "cp-9",         # Information system backup
        "rotation": "ia-5",         # Authenticator management
    },
    # --- SPARC app container tools (consumed from sparc-compliance-latest HDF artifacts) ---
    "grype": {
        "default": "si-2",          # Flaw remediation (image vulns)
        "CRITICAL": "si-2",
        "HIGH": "si-2",
    },
    "cyclonedx-sbom": {
        "default": "cm-8",          # Component inventory
    },
}


def _detect_component(hdf_data):
    """Return the component label from an HDF's profile metadata, or None.

    sparc-validate emits one HDF per CIS profile (e.g. ``cis-postgresql``,
    ``cis-aws-foundations``), with the profile name in ``profiles[0].name``.
    The component label is the structural key the OSCAL emitter uses to
    distinguish controls from different scan targets — `cis-aws-compute §3.3`
    and `cis-docker §5.16` may both map to NIST cm-7, but they're different
    controls and need different stable UUIDs.

    By keying on ``(component, control_id)`` instead of substring-matching the
    control ID, the emitter is robust to upstream control-ID format changes
    (sparc-validate#38: ``sparc-X-N.M`` → ``cis-X-N.M``;
    sparc-validate#39: ``cis-X-N.M`` → SAF's ``C-N.N.N.N``).

    Returns the literal profile name (e.g. ``"cis-postgresql"``), or ``None``
    when the HDF was produced by a tool that doesn't ship a profile name
    (Brakeman, CodeQL, Trivy, …) — in which case callers fall back to
    :func:`detect_tool` for the legacy tool-name keying.
    """
    profiles = hdf_data.get("profiles", [])
    if not profiles:
        return None
    name = profiles[0].get("name")
    if not isinstance(name, str):
        return None
    name = name.strip()
    return name or None


def detect_tool(hdf_data):
    """Detect which tool produced the HDF file."""
    profiles = hdf_data.get("profiles", [])
    if profiles:
        name = profiles[0].get("name", "").lower()
        for tool in TOOL_CONTROL_MAPPING:
            if tool.replace("-", "") in name.replace("-", "").replace("_", ""):
                return tool

    passthrough = hdf_data.get("passthrough", {})
    if isinstance(passthrough, dict):
        raw = passthrough.get("raw", {})
        if isinstance(raw, dict) and "runs" in raw:
            tool_name = (
                raw.get("runs", [{}])[0]
                .get("tool", {})
                .get("driver", {})
                .get("name", "")
                .lower()
            )
            if "brakeman" in tool_name:
                return "brakeman"
            if "codeql" in tool_name:
                return "codeql"
            if "gitleaks" in tool_name:
                return "gitleaks"
            if "trivy" in tool_name:
                return "trivy-fs"
            if "semgrep" in tool_name:
                return "semgrep"
            if "checkov" in tool_name:
                return "checkov"
            if "pip-audit" in tool_name or "pip_audit" in tool_name:
                return "pip-audit"
            if "grype" in tool_name:
                return "grype"

    return "unknown"


def convert_hdf_to_oscal(hdf_data, component, system_name, config):
    """Convert a single HDF file to OSCAL Assessment Results.

    ``component`` is the structural key for stable-UUID derivation — either a
    profile name (``"cis-postgresql"``) for sparc-validate-produced HDFs or a
    tool name (``"checkov"``) for tool-produced HDFs. Observation, finding,
    and result UUIDs are derived deterministically from
    ``(component, control_id)`` so repeat scans with identical outputs produce
    identical documents and the content-stable write helper can skip rewrites.

    The component-keyed shape is robust to upstream control-ID format changes
    (sparc-validate#38, sparc-validate#39) because the control_id flows
    through opaquely.
    """
    now = now_iso()
    mapping = TOOL_CONTROL_MAPPING.get(component, {"default": "cm-2"})

    observations = []
    findings = []
    passed = 0
    failed = 0

    # Inheritance accumulation (#187). Populated only when a control carries
    # implementation_status: inherited; left empty otherwise so HDFs without
    # the new tags produce byte-identical SARs to pre-#187 (regression-safe).
    inherited_requirements = []
    attestations_seen = set()

    for profile in hdf_data.get("profiles", []):
        for control in profile.get("controls", []):
            control_id_raw = control.get("id", "")
            title = control.get("title", control_id_raw)
            # HDF status can be at control level or in results array
            status = control.get("status", "")
            if not status:
                results = control.get("results", [])
                if results:
                    status = results[0].get("status", "unknown")
                else:
                    status = "unknown"

            nist_control = mapping.get("default", "cm-2")
            for tag in control.get("tags", {}).get("nist", []):
                if isinstance(tag, str) and len(tag) >= 2:
                    nist_control = tag.lower().replace(" ", "-")
                    break

            impl_status, inherited_from, attestation_refs = _read_implementation_status(control)

            obs_uuid = stable_uuid(config, "sar-obs", component, control_id_raw)
            is_pass = status in ("passed", "not_applicable", "not_reviewed")

            if is_pass:
                passed += 1
            else:
                failed += 1

            observations.append({
                "uuid": obs_uuid,
                "title": f"{'PASS' if is_pass else 'FAIL'}: {title}",
                "description": control.get("desc", title),
                "methods": ["AUTOMATED"],
                "collected": now,
                "remarks": f"Source: {component}, Status: {status}",
            })

            finding = {
                "uuid": stable_uuid(config, "sar-finding", component, control_id_raw),
                "title": title,
                "description": control.get("desc", ""),
                "target": {
                    "type": "objective-id",
                    "target-id": nist_control,
                    "status": {
                        "state": "satisfied" if is_pass else "not-satisfied"
                    },
                },
                "related-observations": [{"observation-uuid": obs_uuid}],
            }

            # When sparc-validate tags the control with one of the legal
            # OSCAL implementation-status enums, surface it as a custom prop
            # on the finding. 'inherited' is handled separately below — it
            # rides on local-definitions, not as a flat enum.
            if impl_status in LEGAL_IMPLEMENTATION_STATUS:
                finding.setdefault("props", []).append({
                    "ns": SPARC_VALIDATE_PROP_NS,
                    "name": "implementation-status",
                    "value": impl_status,
                })

            # Inherited path: build an implemented-requirement entry that
            # references the AWS attestation resources via OSCAL by-component
            # inheritance modelling. The component itself is added to
            # local-definitions outside this loop, once.
            if impl_status == "inherited":
                attestations_seen.update(attestation_refs)
                inherited_links = [
                    {
                        "href": "#" + _attestation_uuid(config, ref),
                        "rel": "attestation",
                        "text": ref,
                    }
                    for ref in attestation_refs
                ]
                inherited_block = {
                    "uuid": stable_uuid(config, "sar-inherited", component, control_id_raw),
                    "description": (
                        f"Inherited from {inherited_from or 'aws-shared-responsibility'}. "
                        "AWS satisfies this control under the shared-responsibility "
                        "model; customer evidence is the cited AWS attestation(s)."
                    ),
                }
                if inherited_links:
                    inherited_block["links"] = inherited_links
                inherited_requirements.append({
                    "uuid": stable_uuid(config, "sar-inherited-req", component, control_id_raw),
                    "control-id": nist_control,
                    "by-components": [
                        {
                            "component-uuid": stable_uuid(config, "aws-cloud-provider", "component"),
                            "uuid": stable_uuid(config, "sar-inherited-by-comp", component, control_id_raw),
                            "description": (
                                f"Control {nist_control} for HDF item '{control_id_raw}' "
                                "is satisfied by AWS under the shared-responsibility model."
                            ),
                            "implementation-status": {
                                "state": "implemented",
                                "remarks": (
                                    "Operator-side considers this implemented because the cloud "
                                    "service provider satisfies the control responsibility."
                                ),
                            },
                            "inherited": [inherited_block],
                        }
                    ],
                })
                # Tag the finding so consumers can still see the inheritance
                # without parsing local-definitions.
                finding.setdefault("props", []).append({
                    "ns": SPARC_VALIDATE_PROP_NS,
                    "name": "implementation-status",
                    "value": "inherited",
                })

            findings.append(finding)

    result = {
        "uuid": stable_uuid(config, system_name, component, "result"),
        "title": f"{component} Scan",
        "description": f"Passed: {passed}, Failed: {failed}",
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

    # When inheritance is claimed, surface the AWS provider component and
    # the implemented-requirements that pin the inheritance to specific
    # attestations. Stays absent otherwise so SARs from non-inheritance-tagged
    # HDFs are byte-identical to pre-#187 output.
    if inherited_requirements:
        result["local-definitions"] = {
            "components": [_aws_provider_component(config)],
            "control-implementations": [
                {
                    "uuid": stable_uuid(config, system_name, component, "ci-inherited"),
                    "source": "https://raw.githubusercontent.com/usnistgov/oscal-content/main/nist.gov/SP800-53/rev5/json/NIST_SP-800-53_rev5_catalog.json",
                    "description": "Implemented requirements satisfied via inheritance from the cloud service provider.",
                    "implemented-requirements": inherited_requirements,
                }
            ],
        }

    sar = {
        "assessment-results": {
            "metadata": {
                "title": f"{system_name} Assessment Results — {component}",
                "version": "1.0.0",
                "oscal-version": "1.1.2",
                "roles": [
                    {"id": "assessor", "title": f"Automated Assessor ({component})"}
                ],
                "parties": [
                    get_tool_party(config, component)
                ],
            },
            "import-ap": {
                "href": "#assessment-plan",
            },
            "results": [result],
        }
    }

    if attestations_seen:
        sar["assessment-results"]["back-matter"] = {
            "resources": _aws_attestation_resources(config, attestations_seen),
        }

    return sar, passed, failed


def main():
    parser = argparse.ArgumentParser(
        description="Convert SAF HDF files to OSCAL Assessment Results"
    )
    parser.add_argument("--hdf-dir", required=True, help="Directory containing HDF JSON files")
    parser.add_argument("--system-name", required=True, help="System name")
    parser.add_argument("--output-dir", required=True, help="Output directory for OSCAL SARs")
    parser.add_argument("--config", default="organization_variables.yml", help="Organization config YAML")
    args = parser.parse_args()

    config = load_config(args.config)

    os.makedirs(args.output_dir, exist_ok=True)

    total_files = 0
    total_passed = 0
    total_failed = 0

    for filename in sorted(os.listdir(args.hdf_dir)):
        if not filename.endswith(".hdf.json"):
            continue

        filepath = os.path.join(args.hdf_dir, filename)
        print(f"Processing {filename}...")

        with open(filepath) as f:
            hdf_data = json.load(f)

        # Prefer the explicit profile-name component label (sparc-validate
        # CIS HDFs) over heuristic tool detection. Falls through to the
        # tool-name path for tool-style HDFs (Brakeman, Trivy, …).
        component = _detect_component(hdf_data)
        if component is None:
            component = detect_tool(hdf_data)
            if component == "unknown":
                component = filename.replace(".hdf.json", "")

        print(f"  Detected component: {component}")

        sar, passed, failed = convert_hdf_to_oscal(hdf_data, component, args.system_name, config)
        print(f"  Passed: {passed}, Failed: {failed}")

        output_file = os.path.join(args.output_dir, f"{component}-sar.json")
        marker_dir = os.environ.get("OSCAL_CHANGE_MARKERS")
        changed = maybe_write_oscal(output_file, sar, "assessment-results", marker_dir=marker_dir)
        if changed:
            print(f"  Written to {output_file} (content changed — new document UUID minted)")
        else:
            print(f"  Unchanged at {output_file} — preserved prior document UUID")
        total_files += 1
        total_passed += passed
        total_failed += failed

    print(f"\nProcessed {total_files} HDF files")
    print(f"Total: {total_passed} passed, {total_failed} failed")


if __name__ == "__main__":
    main()
