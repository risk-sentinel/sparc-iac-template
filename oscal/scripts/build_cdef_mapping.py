#!/usr/bin/env python3
"""Build a published OSCAL 1.2 mapping-collection: AWS controls -> NIST 800-53.

Repeatable, shareable, and **revision-parameterized** — the recurring real-world
question is "which regulation does a user need, Rev 4 or Rev 5?", so this emits a
mapping-collection at whichever the caller asks for (``--target-rev {4,5}``):

  * source = AWS Config rules (the AWS control layer)
  * target = NIST SP 800-53 rev4 (as published by MITRE's awsconfig mappings) or
    rev5 (translated through the vendored NIST rev4->rev5 crosswalk)

The result is a self-contained OSCAL 1.2.1 ``mapping-collection`` that loads into
SPARC as a published, reusable artifact (matches SPARC's OscalMappingExportService
shape: mappings[] -> {source-resource, target-resource, maps[{relationship,
sources[{type,id-ref}], targets[{type,id-ref}]}]}).

Scope the AWS controls two ways:
  --state <tfstate>   only the AWS Config rules actually DEPLOYED (repeatable, exact)
  --all-rules         every rule in the awsconfig mapping table (generic/shareable)

Determinism: all UUIDs are uuid5-derived and ``--last-modified`` is an explicit
arg, so re-runs produce byte-identical output (clean diffs, drift-checkable).

Example:
  build_cdef_mapping.py --state sparc-config.tfstate --target-rev 5 \
    --awsconfig-mappings oscal/mappings/awsconfig-nist-mappings.json \
    --crosswalk oscal/mappings/nist_r4_to_r5.json \
    --last-modified 2026-07-27T00:00:00Z \
    --output oscal/mappings/aws-config-to-nist80053r5.mapping.json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import tempfile
import uuid

# Fixed namespace so uuid5-derived ids are stable across runs/machines.
NS = uuid.UUID("6f4b0e2a-2f1c-5e7a-9c3d-2a7b1e0f5c88")
OSCAL_VERSION = "1.2.1"
# OSCAL mapping relationship token. A Config-rule check functionally satisfies the
# mapped NIST control(s); "equivalent-to" is the crosswalk convention. method-type
# is automation, matching-rationale functional (recorded as props).
RELATIONSHIP = "equivalent-to"

NIST_R5_CATALOG = ("https://raw.githubusercontent.com/usnistgov/oscal-content/main/"
                   "nist.gov/SP800-53/rev5/json/NIST_SP-800-53_rev5_catalog.json")
NIST_R4_CATALOG = ("https://raw.githubusercontent.com/usnistgov/oscal-content/main/"
                   "nist.gov/SP800-53/rev4/json/NIST_SP-800-53_rev4_catalog.json")


def duuid(*parts: str) -> str:
    return str(uuid.uuid5(NS, "|".join(parts)))


def load_state(ref: str) -> dict:
    if ref.startswith("s3://"):
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".tfstate")
        tmp.close()
        try:
            subprocess.run(["aws", "s3", "cp", ref, tmp.name],
                           check=True, capture_output=True)
            with open(tmp.name) as fh:
                return json.load(fh)
        finally:
            os.unlink(tmp.name)
    with open(ref) as fh:
        return json.load(fh)


def deployed_config_rules(states: list[dict]) -> list[tuple[str, str]]:
    """Return sorted (rule_name, source_identifier) for deployed aws_config_config_rule."""
    out: set[tuple[str, str]] = set()
    for st in states:
        for r in st.get("resources", []):
            if r.get("mode") == "managed" and r.get("type") == "aws_config_config_rule":
                for inst in r.get("instances", []):
                    a = inst.get("attributes", {})
                    name = a.get("name") or ""
                    src = ""
                    for s in a.get("source", []) or []:
                        src = s.get("source_identifier") or src
                    out.add((name, src))
    return sorted(out)


def norm_nist(cid: str) -> str:
    """Canonical NIST id: AC-02 -> AC-2, AC-2(01) -> AC-2(1), keep part letters."""
    m = re.match(r"([A-Z]{2})-0*(\d+)(?:\((\w+)\))?", cid.strip())
    if not m:
        return cid.strip()
    out = f"{m.group(1)}-{m.group(2)}"
    if m.group(3):
        out += f"({m.group(3)})"
    return out


def to_target_rev(ids: list[str], target_rev: int, crosswalk: dict) -> list[str]:
    """Translate rev4 NIST ids to the target revision (identity for rev4)."""
    if target_rev == 4:
        return sorted({norm_nist(c) for c in ids})
    redirects = crosswalk.get("withdrawn_incorporated", {})
    out: set[str] = set()
    for c in ids:
        n = norm_nist(c)
        # strip a trailing part letter (AC-2(g)) to its base for redirect lookup
        base = re.sub(r"\(([a-z])\)$", "", n)
        if n in redirects:
            out.update(redirects[n])
        elif base in redirects:
            out.update(redirects[base])
        else:
            out.add(n)  # carries over identically
    return sorted(out)


def build_maps(rules: list[tuple[str, str]], cfg_by_src: dict, cfg_by_name: dict,
               target_rev: int, crosswalk: dict) -> tuple[list, list, dict]:
    """Return (maps, unmapped_rules, stats)."""
    maps = []
    unmapped = []
    covered_nist: set[str] = set()
    for name, src in rules:
        rev4 = cfg_by_src.get(src) or cfg_by_name.get(name)
        if not rev4:
            unmapped.append(name or src)
            continue
        nist = to_target_rev(rev4.split("|"), target_rev, crosswalk)
        covered_nist.update(nist)
        source_key = name or src
        maps.append({
            "uuid": duuid("map", str(target_rev), source_key),
            "relationship": RELATIONSHIP,
            "matching-rationale": "functional",
            "sources": [{"type": "control", "id-ref": source_key}],
            "targets": [{"type": "control", "id-ref": c.lower()} for c in nist],
        })
    stats = {"rules_mapped": len(maps), "rules_unmapped": len(unmapped),
             "distinct_nist_controls": len(covered_nist)}
    return sorted(maps, key=lambda m: m["sources"][0]["id-ref"]), unmapped, stats


def build_collection(maps: list, target_rev: int, title: str, last_modified: str,
                     provenance: list[str]) -> dict:
    rev_label = f"NIST SP 800-53 rev{target_rev}"
    target_href = NIST_R5_CATALOG if target_rev == 5 else NIST_R4_CATALOG
    src_uuid = duuid("resource", "aws-config-rules")
    tgt_uuid = duuid("resource", f"nist-80053-r{target_rev}")
    return {
        "$schema": "http://csrc.nist.gov/ns/oscal/1.2.1/oscal-mapping-schema.json",
        "mapping-collection": {
            "uuid": duuid("collection", str(target_rev), title),
            "metadata": {
                "title": title,
                "last-modified": last_modified,
                "version": "1.0.0",
                "oscal-version": OSCAL_VERSION,
                "remarks": "Auto-generated by oscal/scripts/build_cdef_mapping.py "
                           "from MITRE awsconfig->NIST mappings"
                           + (" + NIST rev4->rev5 crosswalk." if target_rev == 5 else "."),
            },
            "provenance": {
                "method": "automation",
                "matching-rationale": "functional",
                "status": "complete",
                "mapping-description":
                    f"AWS Config rules mapped to {rev_label} via MITRE hdf-libs "
                    "awsconfig-mappings"
                    + (" translated rev4->rev5 through the NIST comparison workbook."
                       if target_rev == 5 else " (rev4, as published)."),
            },
            "back-matter": {"resources": [
                {"uuid": src_uuid, "title": "AWS Config Rules",
                 "props": [{"name": "type", "value": "aws-config-rules"}]},
                {"uuid": tgt_uuid, "title": rev_label,
                 "rlinks": [{"href": target_href}]},
            ] + [{"uuid": duuid("prov", p), "title": p} for p in provenance]},
            "mappings": [{
                "uuid": duuid("mapping", str(target_rev)),
                "source-resource": {"type": "catalog", "href": f"#{src_uuid}"},
                "target-resource": {"type": "catalog", "href": f"#{tgt_uuid}"},
                "maps": maps,
            }],
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Build AWS->NIST OSCAL 1.2 mapping-collection")
    scope = ap.add_mutually_exclusive_group(required=True)
    scope.add_argument("--state", action="append",
                       help="tfstate (local or s3://); scope to DEPLOYED Config rules")
    scope.add_argument("--all-rules", action="store_true",
                       help="map every rule in the awsconfig table (generic)")
    ap.add_argument("--target-rev", type=int, choices=[4, 5], required=True)
    ap.add_argument("--awsconfig-mappings", default="oscal/mappings/awsconfig-nist-mappings.json")
    ap.add_argument("--crosswalk", default="oscal/mappings/nist_r4_to_r5.json")
    ap.add_argument("--last-modified", required=True,
                    help="ISO datetime for metadata (explicit → reproducible output)")
    ap.add_argument("--title", default="")
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    with open(args.awsconfig_mappings) as fh:
        table = json.load(fh)
    cfg_by_src = {e["AwsConfigRuleSourceIdentifier"]: e["NIST-ID"] for e in table}
    cfg_by_name = {e["AwsConfigRuleName"]: e["NIST-ID"] for e in table}
    crosswalk = json.load(open(args.crosswalk)) if args.target_rev == 5 else {}

    if args.all_rules:
        rules = sorted({(e["AwsConfigRuleName"], e["AwsConfigRuleSourceIdentifier"])
                        for e in table})
        scope_label = "all AWS Config rules"
    else:
        rules = deployed_config_rules([load_state(s) for s in args.state])
        scope_label = f"{len(rules)} deployed AWS Config rules"

    maps, unmapped, stats = build_maps(rules, cfg_by_src, cfg_by_name,
                                       args.target_rev, crosswalk)
    title = args.title or f"AWS Config Rules -> NIST SP 800-53 rev{args.target_rev}"
    provenance = [
        "MITRE hdf-libs awsconfig-mappings (Config rule -> NIST 800-53 rev4)",
    ] + (["NIST sp800-53r4-to-r5 comparison workbook (rev4->rev5 crosswalk)"]
         if args.target_rev == 5 else [])
    coll = build_collection(maps, args.target_rev, title, args.last_modified, provenance)

    with open(args.output, "w") as fh:
        json.dump(coll, fh, indent=2)
        fh.write("\n")
    print(f"wrote {args.output}: {scope_label} -> rev{args.target_rev} | "
          f"{stats['rules_mapped']} mapped, {stats['rules_unmapped']} unmapped, "
          f"{stats['distinct_nist_controls']} distinct NIST controls")
    if unmapped:
        print("  unmapped rules:", ", ".join(unmapped[:8]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
