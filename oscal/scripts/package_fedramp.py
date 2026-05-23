#!/usr/bin/env python3
"""
Assemble a complete FedRAMP 20x authorization package.

Collects all OSCAL artifacts (SSP, SAP, SAR, POA&M, SBOMs)
from infrastructure and application scans into a single
distributable package.

Usage:
    python3 package_fedramp.py \
        --pattern ecs \
        --output-dir fedramp-package/
"""

import argparse
import glob
import json
import os
import shutil
from datetime import datetime, timezone


def collect_file(src, dst_dir, category):
    """Copy a file to the package directory."""
    if os.path.exists(src):
        dst = os.path.join(dst_dir, category, os.path.basename(src))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        return True
    return False


def build_manifest(package_dir, pattern):
    """Generate a manifest of all package contents."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    files = []

    for root, _, filenames in os.walk(package_dir):
        for filename in sorted(filenames):
            if filename == "manifest.json":
                continue
            filepath = os.path.join(root, filename)
            relpath = os.path.relpath(filepath, package_dir)
            size = os.path.getsize(filepath)
            files.append({
                "path": relpath,
                "size_bytes": size,
                "type": "json" if filename.endswith(".json") else "text",
            })

    manifest = {
        "fedramp-20x-package": {
            "title": f"SPARC {pattern.upper()} FedRAMP 20x Authorization Package",
            "generated": now,
            "baseline": "NIST SP 800-53 Rev 5 HIGH Impact",
            "pattern": pattern,
            "contents": {
                "total_files": len(files),
                "categories": {
                    "ssp": len([f for f in files if f["path"].startswith("ssp/")]),
                    "sap": len([f for f in files if f["path"].startswith("sap/")]),
                    "sar/infrastructure": len([f for f in files if "sar/infrastructure" in f["path"]]),
                    "sar/application": len([f for f in files if "sar/application" in f["path"]]),
                    "sar/pipeline": len([f for f in files if "sar/pipeline" in f["path"]]),
                    "poam": len([f for f in files if f["path"].startswith("poam/")]),
                    "sbom": len([f for f in files if f["path"].startswith("sbom/")]),
                    "profile": len([f for f in files if f["path"].startswith("profile/")]),
                },
                "files": files,
            },
        }
    }

    manifest_path = os.path.join(package_dir, "manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    return manifest


def main():
    parser = argparse.ArgumentParser(description="Assemble FedRAMP 20x package")
    parser.add_argument("--pattern", required=True, choices=["ecs", "ec2", "azure-vm", "config"])
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--app-hdf-dir", default="", help="SPARC app HDF directory (optional)")
    parser.add_argument("--app-sbom-dir", default="", help="SPARC app SBOM directory (optional)")
    parser.add_argument(
        "--marker-dir",
        default=os.environ.get("OSCAL_CHANGE_MARKERS", ""),
        help="Directory containing *.changed markers from OSCAL generators. "
        "If set and the directory is empty (or has no markers for this "
        "pattern's inputs), packaging is skipped — prior artifacts are "
        "still valid and a new bundle would be identical content-wise.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Package even when no change markers are present.",
    )
    args = parser.parse_args()

    pkg = args.output_dir
    pattern = args.pattern

    # Short-circuit if no OSCAL generator wrote anything this run. The FedRAMP
    # bundle is purely a copy of the source OSCAL artifacts, so if none of
    # them changed there is no new content to ship.
    if args.marker_dir and os.path.isdir(args.marker_dir) and not args.force:
        markers = glob.glob(os.path.join(args.marker_dir, "*.changed"))
        relevant = [
            m for m in markers
            if pattern in os.path.basename(m) or "assessment-plan" in os.path.basename(m)
        ]
        if not relevant:
            print(
                f"No change markers for pattern '{pattern}' in {args.marker_dir} — "
                f"skipping FedRAMP package regeneration (prior artifacts are still valid)."
            )
            return

    os.makedirs(pkg, exist_ok=True)
    print(f"Assembling FedRAMP 20x package for {pattern}...")

    # SSP
    ssp_file = f"oscal/ssp/sparc-{pattern}-ssp.json"
    if collect_file(ssp_file, pkg, "ssp"):
        print(f"  SSP: {ssp_file}")
    gaps_file = f"oscal/ssp/sparc-{pattern}-ssp-gaps.txt"
    collect_file(gaps_file, pkg, "ssp")

    # SAP
    collect_file("oscal/sap/sparc-assessment-plan.json", pkg, "sap")
    print("  SAP: sparc-assessment-plan.json")

    # Infrastructure SAR
    infra_sar = f"oscal/sar/sparc-{pattern}-sar.json"
    if collect_file(infra_sar, pkg, "sar/infrastructure"):
        print(f"  SAR (infra): {infra_sar}")

    # Application SARs (from HDF conversion)
    app_sar_dir = "oscal/sar/application"
    if os.path.isdir(app_sar_dir):
        for f in sorted(os.listdir(app_sar_dir)):
            if f.endswith("-sar.json"):
                collect_file(os.path.join(app_sar_dir, f), pkg, "sar/application")
                print(f"  SAR (app): {f}")

    # Pipeline SARs (from security scanning HDF conversion)
    pipeline_sar_dir = "oscal/sar/pipeline"
    if os.path.isdir(pipeline_sar_dir):
        for f in sorted(os.listdir(pipeline_sar_dir)):
            if f.endswith("-sar.json"):
                collect_file(os.path.join(pipeline_sar_dir, f), pkg, "sar/pipeline")
                print(f"  SAR (pipeline): {f}")

    # POA&M
    poam_file = f"oscal/poam/sparc-{pattern}-poam.json"
    if collect_file(poam_file, pkg, "poam"):
        print(f"  POA&M: {poam_file}")

    # Profile
    profile = "docs/FedRAMP_20x/NIST_SP-800-53_rev5_HIGH-baseline-resolved-profile_catalog.json"
    if collect_file(profile, pkg, "profile"):
        print("  Profile: HIGH baseline")

    # App SBOMs (if provided)
    if args.app_sbom_dir and os.path.isdir(args.app_sbom_dir):
        for f in sorted(os.listdir(args.app_sbom_dir)):
            if f.endswith(".json") or f.endswith(".xml"):
                collect_file(os.path.join(args.app_sbom_dir, f), pkg, "sbom")
                print(f"  SBOM: {f}")

    # Generate manifest
    manifest = build_manifest(pkg, pattern)
    total = manifest["fedramp-20x-package"]["contents"]["total_files"]
    print(f"\nPackage assembled: {total} files in {pkg}/")
    print(f"Manifest: {pkg}/manifest.json")


if __name__ == "__main__":
    main()
