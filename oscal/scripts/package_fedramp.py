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
import subprocess
import sys
from datetime import datetime, timezone

# A same-run package should contain same-run artifacts. Anything older than this
# is the #624 signature: collecting committed copies instead of generated output.
STALENESS_WARN_DAYS = 1


class MissingArtifactError(RuntimeError):
    """A required OSCAL artifact was absent at package time."""


class SanitizationError(RuntimeError):
    """The package could not be proven free of account-identifying data."""


# scripts/public_export/ lives two levels up from oscal/scripts/.
_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_EXPORT_DIR = os.path.join(_REPO_ROOT, "scripts", "public_export")
DEFAULT_SCRUB_MAP = os.path.join(_EXPORT_DIR, "scrub-map.yml")


def _walk_files(root):
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            yield os.path.join(dirpath, name)


def _discard(package_dir, created_dir):
    """Remove a package that failed sanitization.

    Only when this run created the directory. If it already existed the
    operator may have put something there, and deleting it would be a
    surprise — say so loudly instead.
    """
    if created_dir:
        shutil.rmtree(package_dir, ignore_errors=True)
        print(f"Removed {package_dir}/", file=sys.stderr)
    else:
        print(
            f"::error::{package_dir}/ existed before this run, so it was NOT "
            f"removed. It contains UNSANITIZED data — delete it before "
            f"distributing anything.",
            file=sys.stderr,
        )


def sanitize_package(package_dir, scrub_map, created_dir):
    """Scrub the assembled package, then PROVE it is clean or destroy it (#649).

    Sanitization is opt-in because the authoritative bundle must NOT be
    scrubbed: an SSP whose inventory reads `subnet-EXAMPLE0001` cannot tie a
    finding to a resource, which is the thing it exists to do. This path is for
    bundles that leave the boundary.

    Two details that are easy to get wrong:

    * `sanitize.py` rewrites files, which resets their mtimes. `build_manifest`
      derives `staleness_days` from mtime, and that is the #624 tripwire — a
      package carrying committed copies instead of generated output. Sanitizing
      naively would set every mtime to now and make every bundle look fresh, so
      mtimes are snapshotted and restored around the rewrite.
    * On failure the package is REMOVED, not merely reported. `compliance.yml`
      uploads the package directory under `if: always()`, so a bundle that only
      failed a check would still be published. "Either clean or absent" has to
      be literal.
    """
    sanitize_py = os.path.join(_EXPORT_DIR, "sanitize.py")
    verify_py = os.path.join(_EXPORT_DIR, "verify.py")
    for tool in (sanitize_py, verify_py, scrub_map):
        if not os.path.exists(tool):
            raise SanitizationError(f"cannot sanitize — missing {tool}")

    mtimes = {f: os.path.getmtime(f) for f in _walk_files(package_dir)}

    print("")
    print(f"Sanitizing package with {os.path.relpath(scrub_map, _REPO_ROOT)}...")
    scrub = subprocess.run(  # noqa: S603 - fixed argv, never a shell
        [sys.executable, sanitize_py, "--root", package_dir, "--map", scrub_map],
        capture_output=True, text=True, check=False,
    )
    print(scrub.stdout, end="")
    if scrub.returncode != 0:
        print(scrub.stderr, end="", file=sys.stderr)
        _discard(package_dir, created_dir)
        raise SanitizationError("sanitize.py failed — package discarded")

    # Restore artifact generation times (see docstring).
    for path, mtime in mtimes.items():
        if os.path.exists(path):
            os.utime(path, (mtime, mtime))

    check = subprocess.run(  # noqa: S603 - fixed argv, never a shell
        [sys.executable, verify_py, "--root", package_dir, "--map", scrub_map],
        capture_output=True, text=True, check=False,
    )
    print(check.stdout, end="")
    if check.returncode != 0:
        print(check.stderr, end="", file=sys.stderr)
        _discard(package_dir, created_dir)
        raise SanitizationError(
            "verify.py found account-identifying data in the assembled package "
            "— discarded rather than shipped. Add or extend a "
            "pattern_replacements rule in scrub-map.yml and re-run."
        )

    return {
        "sanitized": True,
        "scrub_map": os.path.relpath(scrub_map, _REPO_ROOT),
        "verified_by": "scripts/public_export/verify.py",
    }


def collect_file(src, dst_dir, category, missing=None):
    """Copy a file to the package directory.

    `missing` is an accumulator list. When supplied, a src that does not exist
    is recorded so main() can fail the build. A package silently missing its
    SAR or POA&M is worse than a failed build (#624) — the failure has to be
    loud, because the artifact is consumed downstream as evidence.
    """
    if os.path.exists(src):
        dst = os.path.join(dst_dir, category, os.path.basename(src))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        return True
    if missing is not None:
        missing.append(src)
    return False


def is_sar(filename):
    """True for OSCAL SAR files from either naming convention.

    The `hdf` CLI writes `<base>.sar.json` (dot) while our own generators emit
    `<pattern>-sar.json` (hyphen). The original filter required the hyphen, so
    every application and pipeline SAR was silently skipped (#624) — the
    directories were always correct, the suffix test was not.
    """
    return filename.endswith("sar.json")


def build_manifest(package_dir, pattern, sanitization=None):
    """Generate a manifest of all package contents."""
    now_dt = datetime.now(timezone.utc)
    now = now_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    files = []
    newest_mtime = None

    for root, _, filenames in os.walk(package_dir):
        for filename in sorted(filenames):
            if filename == "manifest.json":
                continue
            filepath = os.path.join(root, filename)
            relpath = os.path.relpath(filepath, package_dir)
            size = os.path.getsize(filepath)
            # copy2 preserves mtime, so this is the artifact's own generation
            # time — the signal that makes staleness visible in the package
            # itself rather than only by cross-referencing S3 (#624).
            mtime = os.path.getmtime(filepath)
            if newest_mtime is None or mtime > newest_mtime:
                newest_mtime = mtime
            files.append({
                "path": relpath,
                "size_bytes": size,
                "type": "json" if filename.endswith(".json") else "text",
                "generated": datetime.fromtimestamp(
                    mtime, timezone.utc
                ).strftime("%Y-%m-%dT%H:%M:%SZ"),
            })

    newest = (
        datetime.fromtimestamp(newest_mtime, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        if newest_mtime
        else None
    )
    staleness_days = (
        int((now_dt.timestamp() - newest_mtime) // 86400) if newest_mtime else None
    )

    manifest = {
        "fedramp-20x-package": {
            "title": f"SPARC {pattern.upper()} FedRAMP 20x Authorization Package",
            "generated": now,
            "baseline": "NIST SP 800-53 Rev 5 HIGH Impact",
            "pattern": pattern,
            # Enough provenance to detect a #624-class regression from the
            # artifact alone. If newest_artifact lags `generated` by more than
            # a run, the package is carrying stale inputs.
            "provenance": {
                "newest_artifact": newest,
                "staleness_days": staleness_days,
                "expected_staleness_days": 0,
            },
            # A sanitized bundle says so in its own manifest. Reading a
            # README to find out whether a package is safe to forward is the
            # kind of provenance that goes missing in transit (#649).
            "sanitization": sanitization or {"sanitized": False},
            "contents": {
                "total_files": len(files),
                "categories": {
                    "ssp": len([f for f in files if f["path"].startswith("ssp/")]),
                    "sap": len([f for f in files if f["path"].startswith("sap/")]),
                    # S1192 (#526): derive the sar/* counts from a single tuple.
                    **{k: len([f for f in files if k in f["path"]])
                       for k in ("sar/infrastructure", "sar/application", "sar/pipeline")},
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


def main():  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
    parser = argparse.ArgumentParser(description="Assemble FedRAMP 20x package")
    parser.add_argument("--pattern", required=True, choices=["ecs", "ec2", "azure-vm", "aas", "ack"])
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
    parser.add_argument(
        "--sanitize",
        action="store_true",
        help="Scrub account-identifying data from the assembled package and "
        "PROVE it clean with verify.py, discarding the package if that fails "
        "(#649). Off by default: the authoritative bundle must keep real "
        "identifiers or a finding cannot be tied to a resource. Use for any "
        "bundle that leaves the boundary.",
    )
    parser.add_argument(
        "--scrub-map",
        default=DEFAULT_SCRUB_MAP,
        help="scrub-map.yml to apply with --sanitize.",
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

    created_dir = not os.path.isdir(pkg)
    os.makedirs(pkg, exist_ok=True)
    print(f"Assembling FedRAMP 20x package for {pattern}...")

    # Paths below MUST match what compliance.yml actually generates. They
    # previously carried a `sparc-` prefix that no generator emits, so the
    # packager collected the stale committed copies instead and shipped March
    # data for months without erroring (#624). Keep these in step with
    # compliance.yml — the generator is the source of truth for the names.
    missing = []

    # SSP
    ssp_file = f"oscal/ssp/{pattern}-ssp.json"
    if collect_file(ssp_file, pkg, "ssp", missing):
        print(f"  SSP: {ssp_file}")
    # assemble_ssp.py writes the gap report as .md (args.output with
    # .json -> -gaps.md); the packager looked for .txt, so it never collected
    # one. Optional, so not in `missing`.
    gaps_file = f"oscal/ssp/{pattern}-ssp-gaps.md"
    if collect_file(gaps_file, pkg, "ssp"):
        print(f"  SSP gaps: {gaps_file}")

    # SAP — static; nothing generates this per-run (see #624 note on staleness).
    collect_file("oscal/sap/sparc-assessment-plan.json", pkg, "sap", missing)
    print("  SAP: sparc-assessment-plan.json")

    # Infrastructure SAR
    infra_sar = f"oscal/sar/{pattern}-sar.json"
    if collect_file(infra_sar, pkg, "sar/infrastructure", missing):
        print(f"  SAR (infra): {infra_sar}")

    # Application SARs (from HDF conversion)
    app_sar_dir = "oscal/sar/application"
    if os.path.isdir(app_sar_dir):
        for f in sorted(os.listdir(app_sar_dir)):
            if is_sar(f):
                collect_file(os.path.join(app_sar_dir, f), pkg, "sar/application")
                print(f"  SAR (app): {f}")

    # Pipeline SARs (from security scanning HDF conversion)
    pipeline_sar_dir = "oscal/sar/pipeline"
    if os.path.isdir(pipeline_sar_dir):
        for f in sorted(os.listdir(pipeline_sar_dir)):
            if is_sar(f):
                collect_file(os.path.join(pipeline_sar_dir, f), pkg, "sar/pipeline")
                print(f"  SAR (pipeline): {f}")

    # POA&M
    poam_file = f"oscal/poam/{pattern}-poam.json"
    if collect_file(poam_file, pkg, "poam", missing):
        print(f"  POA&M: {poam_file}")

    # Profile
    profile = "docs/FedRAMP_20x/NIST_SP-800-53_rev5_HIGH-baseline-resolved-profile_catalog.json"
    if collect_file(profile, pkg, "profile", missing):
        print("  Profile: HIGH baseline")

    # App SBOMs (if provided)
    if args.app_sbom_dir and os.path.isdir(args.app_sbom_dir):
        for f in sorted(os.listdir(args.app_sbom_dir)):
            if f.endswith((".json", ".xml")):
                collect_file(os.path.join(args.app_sbom_dir, f), pkg, "sbom")
                print(f"  SBOM: {f}")

    # Fail loudly on a missing REQUIRED artifact (#624). Shipping a package
    # that is quietly missing its SAR or POA&M is worse than not shipping one:
    # downstream it reads as "no findings" rather than "not collected".
    if missing:
        raise MissingArtifactError(
            "required OSCAL artifact(s) not found — refusing to ship an "
            "incomplete FedRAMP package:\n  "
            + "\n  ".join(missing)
            + "\n\nThese paths must match what .github/workflows/compliance.yml "
            "generates. If a generator's output name changed, update both."
        )

    # Sanitize BEFORE the manifest so the manifest describes what actually
    # ships — sizes change, and the stamp has to reflect a verified tree.
    sanitization = None
    if args.sanitize:
        sanitization = sanitize_package(pkg, args.scrub_map, created_dir)

    # Generate manifest
    manifest = build_manifest(pkg, pattern, sanitization)
    total = manifest["fedramp-20x-package"]["contents"]["total_files"]
    print(f"\nPackage assembled: {total} files in {pkg}/")
    print(f"Manifest: {pkg}/manifest.json")

    stale = manifest["fedramp-20x-package"]["provenance"]["staleness_days"]
    if stale is not None and stale > STALENESS_WARN_DAYS:
        print(
            f"\n::warning::Newest artifact in this package is {stale} days older "
            f"than the package timestamp. Expected same-run artifacts — this is "
            f"the signature of the #624 regression (collecting committed copies "
            f"instead of generated output). Verify before distributing."
        )


if __name__ == "__main__":
    main()
