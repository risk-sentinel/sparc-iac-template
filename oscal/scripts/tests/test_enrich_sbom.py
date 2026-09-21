"""Tests for enrich_sbom.py (#398).

Covers the BOM enrichment + idempotent merge: terraform providers and pinned
GitHub Actions are added, Syft's purl-less terraform entries are deduped by
name, SHA-pinned-with-comment actions resolve to the comment's semver, and
re-running is a no-op. specVersion is never mutated.
"""

from __future__ import annotations

import json
from pathlib import Path

import enrich_sbom as es

_LOCK = """\
provider "registry.terraform.io/hashicorp/aws" {
  version     = "5.100.0"
  constraints = "~> 5.0"
  hashes = [
    "h1:abc=",
  ]
}

provider "registry.terraform.io/hashicorp/random" {
  version = "3.8.1"
  hashes  = ["h1:def="]
}
"""

_WORKFLOW = """\
name: demo
on: [push]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: risk-sentinel/container-build-sign/.github/workflows/sbom-source.yml@d7ec024eb4642c57bac57a00ade0c31c73ef23b7 # v0.1.0
      - uses: ./.github/actions/local-thing
      - run: echo hi
"""


def _repo(tmp_path: Path) -> Path:
    """Build a tiny repo: one lock file (nested) + one workflow."""
    (tmp_path / "AWS" / "ECS").mkdir(parents=True)
    (tmp_path / "AWS" / "ECS" / ".terraform.lock.hcl").write_text(_LOCK)
    (tmp_path / ".github" / "workflows").mkdir(parents=True)
    (tmp_path / ".github" / "workflows" / "demo.yml").write_text(_WORKFLOW)
    return tmp_path


def _bom(tmp_path: Path, components=None) -> Path:
    bom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "components": components or [],
    }
    p = tmp_path / "cyclonedx.json"
    p.write_text(json.dumps(bom))
    return p


def _run(inp: Path, root: Path, out: Path) -> dict:
    es.main(["--in", str(inp), "--repo-root", str(root), "--out", str(out)])
    return json.loads(out.read_text())


def test_adds_terraform_and_actions(tmp_path):
    root = _repo(tmp_path)
    out = _run(_bom(tmp_path), root, tmp_path / "out.json")
    names = {c["name"] for c in out["components"]}
    purls = {c.get("purl") for c in out["components"]}
    # terraform providers (deduped across files, keyed by source name)
    assert "registry.terraform.io/hashicorp/aws" in names
    assert "registry.terraform.io/hashicorp/random" in names
    assert "pkg:terraform/hashicorp/aws@5.100.0" in purls
    # github actions
    assert "pkg:github/actions/checkout@v6" in purls


def test_sha_pin_uses_comment_semver(tmp_path):
    root = _repo(tmp_path)
    out = _run(_bom(tmp_path), root, tmp_path / "out.json")
    reusable = [
        c for c in out["components"]
        if c["name"].startswith("risk-sentinel/container-build-sign")
    ]
    assert len(reusable) == 1
    # SHA ref + `# v0.1.0` comment -> version is the semver, subpath in purl
    assert reusable[0]["version"] == "v0.1.0"
    assert reusable[0]["purl"] == (
        "pkg:github/risk-sentinel/container-build-sign@v0.1.0"
        "#.github/workflows/sbom-source.yml"
    )


def test_skips_local_uses(tmp_path):
    root = _repo(tmp_path)
    out = _run(_bom(tmp_path), root, tmp_path / "out.json")
    assert not any("local-thing" in c["name"] for c in out["components"])


def test_idempotent(tmp_path):
    root = _repo(tmp_path)
    first = _run(_bom(tmp_path), root, tmp_path / "out.json")
    second = _run(tmp_path / "out.json", root, tmp_path / "out2.json")
    assert len(first["components"]) == len(second["components"])
    assert json.dumps(first, sort_keys=True) == json.dumps(second, sort_keys=True)


def test_dedup_preexisting_syft_terraform_by_name(tmp_path):
    root = _repo(tmp_path)
    # Syft writes terraform entries with NO purl — must dedup on name.
    pre = [{
        "type": "library",
        "name": "registry.terraform.io/hashicorp/aws",
        "version": "5.100.0",
    }]
    out = _run(_bom(tmp_path, pre), root, tmp_path / "out.json")
    aws = [c for c in out["components"]
           if c["name"] == "registry.terraform.io/hashicorp/aws"]
    assert len(aws) == 1  # not duplicated


def test_specversion_preserved(tmp_path):
    root = _repo(tmp_path)
    out = _run(_bom(tmp_path), root, tmp_path / "out.json")
    assert out["specVersion"] == "1.6"


def test_distinct_provider_versions_across_modules(tmp_path):
    # The repo can be mid-major-upgrade: aws 5.x in one module, 6.x in another.
    # Both versions must be represented (dedup is on (name, version), not name).
    root = _repo(tmp_path)
    (root / "bootstrap").mkdir()
    (root / "bootstrap" / ".terraform.lock.hcl").write_text(
        'provider "registry.terraform.io/hashicorp/aws" {\n'
        '  version = "6.46.0"\n  hashes = ["h1:zzz="]\n}\n'
    )
    out = _run(_bom(tmp_path), root, tmp_path / "out.json")
    aws_versions = {
        c["version"] for c in out["components"]
        if c["name"] == "registry.terraform.io/hashicorp/aws"
    }
    assert aws_versions == {"5.100.0", "6.46.0"}
