#!/usr/bin/env python3
"""Enrich a Syft CycloneDX SBOM with sparc-iac's IaC supply-chain (#398).

sparc-iac carries two supply-chain surfaces that no container image SBOM covers
and that Syft may or may not catalog depending on its version:

  * Terraform providers, pinned in ``**/.terraform.lock.hcl``.
  * GitHub Actions, pinned via ``uses:`` across ``.github/workflows/``.

This script reads those pins straight from the repo and merges them into the
CycloneDX BOM that ``sbom-and-sca.yml`` already produces, so the BOM emitted to
the org SCA bucket always represents them — regardless of the Syft version the
reusable ``sbom-source`` workflow ships.

The merge is **idempotent**: components Syft already cataloged are not
duplicated, and re-running on an already-enriched BOM is a no-op. To match
Syft's own output (and so dedup actually collapses):

  * Terraform components are keyed on ``(name, version)`` where name is the full
    ``registry.terraform.io/<ns>/<name>`` source URL — Syft's terraform cataloger
    deliberately omits the PURL (purl-spec#369), so name is the only stable
    identity, and keying on version too preserves distinct versions across
    mid-upgrade modules.
  * GitHub Action components are keyed on the PURL ``pkg:github/<ns>/<name>@…``,
    matching Syft's ``githubactions`` cataloger. When an action is SHA-pinned
    with a trailing ``# vX.Y.Z`` comment, Syft uses the semver from the comment
    as the version; we mirror that so the PURLs line up.

Pure standard library — no third-party dependencies. Parsing is line-based with
plain string operations (no regular expressions) — the inputs are small,
trusted repo files, and avoiding regex keeps the parsing obviously linear.

Usage:
    python3 oscal/scripts/enrich_sbom.py --in cyclonedx.json --repo-root . \
        --out sparc-iac.cdx.json   # --out may equal --in (in-place)
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys

_HEX = set("0123456789abcdef")


def _warn(msg: str) -> None:
    print(f"enrich_sbom: warning: {msg}", file=sys.stderr)


def _quoted(line: str) -> str | None:
    """Return the text inside the first pair of double quotes, or None."""
    a = line.find('"')
    if a == -1:
        return None
    b = line.find('"', a + 1)
    return line[a + 1:b] if b != -1 else None


def _is_commit_sha(ref: str) -> bool:
    return 7 <= len(ref) <= 40 and all(c in _HEX for c in ref.lower())


def _find_semver(text: str) -> str | None:
    """Find a `X.Y.Z` (optionally `vX.Y.Z`) token in free text."""
    for tok in text.replace(",", " ").split():
        core = tok[1:] if tok.startswith("v") else tok
        parts = core.split(".")
        if len(parts) == 3 and all(p.isdigit() for p in parts):
            return tok
    return None


def _read_text(path: str) -> str | None:
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError as exc:  # pragma: no cover - defensive
        _warn(f"skipping unreadable {path}: {exc}")
        return None


def load_bom(path: str) -> dict:
    """Load + sanity-check a CycloneDX JSON BOM."""
    with open(path, encoding="utf-8") as fh:
        bom = json.load(fh)
    if bom.get("bomFormat") != "CycloneDX":
        raise ValueError(f"{path}: not a CycloneDX BOM (bomFormat missing)")
    bom.setdefault("components", [])
    return bom


def existing_keys(bom: dict) -> tuple[set, set]:
    """Build dedup indexes: non-empty PURLs, and (name, version) for terraform.

    Syft writes terraform components with no PURL, so they dedup on
    (name, version) — keyed on version too so distinct provider versions across
    modules (the repo can be mid-major-upgrade) are all preserved.
    """
    purls: set = set()
    tf_keys: set = set()
    for comp in bom.get("components", []):
        purl = comp.get("purl")
        if purl:
            purls.add(purl)
        name = comp.get("name", "")
        if name.startswith("registry.terraform.io/"):
            tf_keys.add((name, comp.get("version", "")))
    return purls, tf_keys


def _component(name: str, version: str, purl: str) -> dict:
    return {"type": "library", "name": name, "version": version,
            "purl": purl, "bom-ref": purl}


def _providers_in_text(text: str, source_path: str):
    """Yield (source, version) for each provider block, scanning line by line."""
    current = None
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith('provider "') and line.endswith("{"):
            current = _quoted(line)
            continue
        if current is None:
            continue
        if line.startswith("version") and "=" in line:
            version = _quoted(line)
            if version:
                yield current, version
            current = None
        elif line == "}":
            _warn(f"{source_path}: provider {current!r} has no version; skipping")
            current = None


def _tf_component(source: str, version: str) -> dict:
    parts = source.split("/")
    name = parts[-1]
    namespace = parts[-2] if len(parts) >= 2 else ""
    purl = (f"pkg:terraform/{namespace}/{name}@{version}" if namespace
            else f"pkg:terraform/{name}@{version}")
    return _component(source, version, purl)


def parse_terraform_locks(repo_root: str) -> list[dict]:
    """Extract provider components from every .terraform.lock.hcl under root."""
    seen: set = set()
    out: list[dict] = []
    pattern = os.path.join(repo_root, "**", ".terraform.lock.hcl")
    for lock in sorted(glob.glob(pattern, recursive=True)):
        text = _read_text(lock)
        if text is None:
            continue
        for source, version in _providers_in_text(text, lock):
            if (source, version) not in seen:
                seen.add((source, version))
                out.append(_tf_component(source, version))
    return out


def _action_version(ref: str, comment: str | None) -> str:
    """Mirror Syft: SHA pin + `# vX.Y.Z` comment -> the comment's semver."""
    if comment and _is_commit_sha(ref):
        sm = _find_semver(comment)
        if sm:
            return sm
    return ref


def _uses_ref(line: str) -> tuple[str, str | None] | None:
    """Pull (ref_spec, comment) from a `uses:` step line, or None."""
    s = line.strip()
    if s.startswith("- "):
        s = s[2:].lstrip()
    if not s.startswith("uses:"):
        return None
    rest = s[len("uses:"):].strip()
    comment = None
    if "#" in rest:
        rest, comment = rest.split("#", 1)
        rest, comment = rest.strip(), comment.strip()
    tokens = rest.split()
    if not tokens:
        return None
    return tokens[0].strip("\"'"), comment


def _action_component(line: str) -> dict | None:
    """Build a component from one `uses:` line, or None if not applicable."""
    parsed = _uses_ref(line)
    if not parsed:
        return None
    ref_spec, comment = parsed
    if ref_spec.startswith("./") or "@" not in ref_spec:
        return None  # local action / no pin
    target, ref = ref_spec.rsplit("@", 1)
    segs = target.split("/")
    if len(segs) < 2:
        return None
    version = _action_version(ref, comment)
    purl = f"pkg:github/{segs[0]}/{segs[1]}@{version}"
    subpath = "/".join(segs[2:])
    if subpath:
        purl += f"#{subpath}"
    return _component(target, version, purl)


def parse_action_uses(repo_root: str) -> list[dict]:
    """Extract GitHub Action components from every workflow `uses:` pin."""
    seen: set = set()
    out: list[dict] = []
    wf_dir = os.path.join(repo_root, ".github", "workflows")
    files = sorted(glob.glob(os.path.join(wf_dir, "*.yml")) +
                   glob.glob(os.path.join(wf_dir, "*.yaml")))
    for wf in files:
        text = _read_text(wf)
        if text is None:
            continue
        for line in text.splitlines():
            comp = _action_component(line)
            if comp and comp["purl"] not in seen:
                seen.add(comp["purl"])
                out.append(comp)
    return out


def merge(bom: dict, candidates: list[dict]) -> int:
    """Append candidates not already present. Returns the count added.

    Terraform dedups on (name, version) (no PURL in Syft output); everything
    else dedups on `purl`. Indexes update as we add so duplicate candidates in
    the same run also collapse.
    """
    purls, tf_keys = existing_keys(bom)
    added = 0
    for comp in candidates:
        name = comp["name"]
        if name.startswith("registry.terraform.io/"):
            key = (name, comp.get("version", ""))
            if key in tf_keys:
                continue
            tf_keys.add(key)
        elif comp["purl"] in purls:
            continue
        else:
            purls.add(comp["purl"])
        bom["components"].append(comp)
        added += 1
    return added


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--in", dest="inp", required=True, help="Syft CycloneDX JSON")
    ap.add_argument("--repo-root", default=".", help="repo root to scan")
    ap.add_argument("--out", required=True, help="output path (may equal --in)")
    args = ap.parse_args(argv)

    bom = load_bom(args.inp)
    tf = parse_terraform_locks(args.repo_root)
    actions = parse_action_uses(args.repo_root)
    added = merge(bom, tf + actions)

    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(bom, fh, indent=2)
        fh.write("\n")

    print(
        f"enrich_sbom: added {added} components "
        f"({len(tf)} terraform providers, {len(actions)} github actions scanned); "
        f"BOM now has {len(bom['components'])} components "
        f"(specVersion {bom.get('specVersion')})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
