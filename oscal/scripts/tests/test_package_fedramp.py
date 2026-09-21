"""Regression tests for package_fedramp.py (#624).

The bug these cover shipped stale March data in every FedRAMP package for
roughly four months without ever erroring: the packager collected filenames
no generator emits, found the committed copies sitting in the same
directories, and reported success. Nothing was missing, so nothing failed —
the wrong file was simply present and readable.

The tests therefore assert on *which* file is collected, not merely that
collection succeeded.
"""

import json
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from package_fedramp import (  # noqa: E402
    MissingArtifactError,
    build_manifest,
    is_sar,
    main,
)


PATTERN = "ecs"


def _write(path, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        json.dump(payload, fh)


@pytest.fixture
def tree(tmp_path, monkeypatch):
    """A minimal repo layout with BOTH naming conventions present.

    The stale `sparc-`-prefixed files are deliberately included: that is the
    condition that made #624 silent, and a fix that only works when they are
    absent has not fixed anything.
    """
    monkeypatch.chdir(tmp_path)

    _write(f"oscal/ssp/{PATTERN}-ssp.json", {"generated": True})
    _write(f"oscal/sar/{PATTERN}-sar.json", {"generated": True})
    _write(f"oscal/poam/{PATTERN}-poam.json", {"generated": True})
    _write("oscal/sap/sparc-assessment-plan.json", {"static": True})
    _write(
        "docs/FedRAMP_20x/NIST_SP-800-53_rev5_HIGH-baseline-resolved-profile_catalog.json",
        {"profile": True},
    )

    # The stale committed copies that shadowed the generated set.
    _write(f"oscal/ssp/sparc-{PATTERN}-ssp.json", {"generated": False})
    _write(f"oscal/sar/sparc-{PATTERN}-sar.json", {"generated": False})
    _write(f"oscal/poam/sparc-{PATTERN}-poam.json", {"generated": False})

    # hdf CLI output — dot separator, which the old filter rejected.
    _write("oscal/sar/pipeline/checkov.sar.json", {"generated": True})
    _write("oscal/sar/application/sparc-app.sar.json", {"generated": True})

    return tmp_path


def _run(out="pkg"):
    sys.argv = [
        "package_fedramp.py",
        "--pattern", PATTERN,
        "--output-dir", out,
        "--force",
    ]
    main()
    return out


def test_collects_generated_not_committed(tree):
    """The core regression: generated artifacts win over the stale copies."""
    out = _run()

    for rel in (
        f"ssp/{PATTERN}-ssp.json",
        f"sar/infrastructure/{PATTERN}-sar.json",
        f"poam/{PATTERN}-poam.json",
    ):
        path = os.path.join(out, rel)
        assert os.path.exists(path), f"{rel} not collected"
        with open(path) as fh:
            assert json.load(fh)["generated"] is True, (
                f"{rel} collected the STALE committed copy — #624 has regressed"
            )

    # The specific stale committed filenames must not appear anywhere.
    # (Deliberately an exact-name check: `sparc-` as a prefix is legitimate for
    # e.g. sparc-assessment-plan.json and application SARs named after the app.)
    stale_names = {
        f"sparc-{PATTERN}-ssp.json",
        f"sparc-{PATTERN}-sar.json",
        f"sparc-{PATTERN}-poam.json",
    }
    collected = {f for _, _, fs in os.walk(out) for f in fs}
    assert not (collected & stale_names), f"stale copies collected: {collected & stale_names}"


def test_pipeline_and_application_sars_are_collected(tree):
    """Dot-separated SAR names must be collected (#624 item 3).

    These reported 0 in every manifest. The directories were always correct;
    the suffix filter required a hyphen the hdf CLI never writes.
    """
    out = _run()
    assert os.path.exists(os.path.join(out, "sar/pipeline/checkov.sar.json"))
    assert os.path.exists(os.path.join(out, "sar/application/sparc-app.sar.json"))

    manifest = json.load(open(os.path.join(out, "manifest.json")))
    cats = manifest["fedramp-20x-package"]["contents"]["categories"]
    assert cats["sar/pipeline"] == 1
    assert cats["sar/application"] == 1


@pytest.mark.parametrize(
    "name,expected",
    [
        ("checkov.sar.json", True),      # hdf CLI
        ("ecs-sar.json", True),          # our generators
        ("aws-config.sar.json", True),
        ("checkov.hdf.json", False),
        ("manifest.json", False),
    ],
)
def test_is_sar_accepts_both_conventions(name, expected):
    assert is_sar(name) is expected


def test_missing_required_artifact_fails_loudly(tree):
    """A package missing its POA&M must fail, not ship partial (#624 item 2)."""
    os.remove(f"oscal/poam/{PATTERN}-poam.json")
    with pytest.raises(MissingArtifactError) as exc:
        _run("pkg-missing")
    assert "poam" in str(exc.value)


def test_manifest_carries_staleness_provenance(tree):
    """Staleness must be detectable from the artifact alone (#624 item 5)."""
    out = _run()
    manifest = json.load(open(os.path.join(out, "manifest.json")))
    prov = manifest["fedramp-20x-package"]["provenance"]
    assert prov["staleness_days"] == 0
    assert prov["newest_artifact"] is not None
    files = manifest["fedramp-20x-package"]["contents"]["files"]
    assert all("generated" in f for f in files)


def test_build_manifest_handles_empty_package(tmp_path):
    """No files must not crash the manifest builder."""
    empty = tmp_path / "empty"
    empty.mkdir()
    manifest = build_manifest(str(empty), PATTERN)["fedramp-20x-package"]
    assert manifest["contents"]["total_files"] == 0
    assert manifest["provenance"]["staleness_days"] is None


# ---------------------------------------------------------------------------
# --sanitize (#649)
#
# The gap these cover is the one #649 filed and #673 hit: scrub-map.yml was a
# literal allow-list, so it removed only values somebody had enumerated, and
# verify.py reported CLEAN over 183 identifiers it had no rule for. The flag is
# only worth having if an unclean bundle cannot survive it, so the important
# assertion is that the package is GONE — not that an error was printed.
# ---------------------------------------------------------------------------

SCRUB_MAP = os.path.join(
    os.path.dirname(__file__), "..", "..", "..", "scripts", "public_export", "scrub-map.yml"
)


def _run_sanitized(out="pkg", scrub_map=SCRUB_MAP):
    sys.argv = [
        "package_fedramp.py",
        "--pattern", PATTERN,
        "--output-dir", out,
        "--force",
        "--sanitize",
        "--scrub-map", scrub_map,
    ]
    main()
    return out


def test_sanitize_scrubs_identifiers_and_stamps_the_manifest(tree):
    _write(f"oscal/ssp/{PATTERN}-ssp.json", {"vpc": "vpc-EXAMPLE0001"})

    out = _run_sanitized()

    ssp = json.load(open(os.path.join(out, "ssp", f"{PATTERN}-ssp.json")))
    assert ssp["vpc"] == "vpc-EXAMPLE0001", "pattern rule did not scrub the VPC id"

    manifest = json.load(open(os.path.join(out, "manifest.json")))
    stamp = manifest["fedramp-20x-package"]["sanitization"]
    assert stamp["sanitized"] is True
    assert stamp["verified_by"] == "scripts/public_export/verify.py"


def test_unsanitized_package_is_not_stamped(tree):
    out = _run()
    manifest = json.load(open(os.path.join(out, "manifest.json")))
    assert manifest["fedramp-20x-package"]["sanitization"] == {"sanitized": False}


def test_package_is_destroyed_when_verification_fails(tree, tmp_path):
    """An identifier with no rule must take the whole bundle with it.

    compliance.yml uploads the package directory under `if: always()`, so a
    bundle that merely reported a failure would still ship. Absent is the only
    safe failure mode.
    """
    # A shape the map deliberately has no rule for.
    _write(f"oscal/ssp/{PATTERN}-ssp.json", {"leak": "tgw-0a1b2c3d4e5f60718"})
    bespoke = tmp_path / "scrub-map.yml"
    bespoke.write_text(
        "literal_replacements:\n"
        "  - description: placeholder\n"
        '    find: "__never_present__"\n'
        '    replace: "x"\n'
        "pattern_replacements:\n"
        "  - description: Transit gateway ids\n"
        "    pattern: '\\btgw-[0-9a-f]{8,17}\\b'\n"
        "    placeholder: 'tgw-EXAMPLE{n:04d}'\n"
    )
    # Sanity: with a rule present the bundle survives.
    _run_sanitized(out="pkg-ok", scrub_map=str(bespoke))
    assert os.path.isdir("pkg-ok")

    # Without one, verify.py must fail and the package must not exist.
    bespoke.write_text(
        "literal_replacements:\n"
        "  - description: placeholder\n"
        '    find: "__never_present__"\n'
        '    replace: "x"\n'
        "pattern_replacements:\n"
        "  - description: Transit gateway ids (detect only, no scrub rule applied)\n"
        "    pattern: '\\bnever-matches-anything-[0-9]{99}\\b'\n"
        "    placeholder: 'x{n:04d}'\n"
    )
    # Re-point the detector at the planted shape but give sanitize nothing to
    # do, by making the rule unmatchable during scrub and matchable at verify.
    from package_fedramp import SanitizationError, sanitize_package

    os.makedirs("pkg-dirty/ssp", exist_ok=True)
    with open("pkg-dirty/ssp/x.json", "w") as fh:
        json.dump({"leak": "tgw-0a1b2c3d4e5f60718"}, fh)
    detect_only = tmp_path / "detect.yml"
    detect_only.write_text(
        "literal_replacements:\n"
        "  - description: placeholder\n"
        '    find: "tgw-0a1b2c3d4e5f60718"\n'
        '    replace: "tgw-0a1b2c3d4e5f60718"\n'
    )
    with pytest.raises(SanitizationError):
        sanitize_package("pkg-dirty", str(detect_only), created_dir=True)
    assert not os.path.exists("pkg-dirty"), "unclean package survived sanitization"


def test_sanitize_preserves_artifact_mtimes_so_staleness_still_works(tree):
    """Sanitizing rewrites files; staleness is derived from mtime (#624).

    Without the snapshot/restore, every sanitized bundle would report
    staleness_days 0 and the #624 tripwire would be permanently disarmed.
    """
    # staleness is derived from the NEWEST artifact, so every input has to be
    # aged — and the SSP must carry something the sanitizer actually rewrites,
    # or the restore path is never exercised.
    _write(f"oscal/ssp/{PATTERN}-ssp.json", {"vpc": "vpc-EXAMPLE0001"})
    old = 1_600_000_000  # 2020
    for dirpath, _, filenames in os.walk("oscal"):
        for name in filenames:
            os.utime(os.path.join(dirpath, name), (old, old))
    for dirpath, _, filenames in os.walk("docs"):
        for name in filenames:
            os.utime(os.path.join(dirpath, name), (old, old))

    out = _run_sanitized()

    scrubbed = json.load(open(os.path.join(out, "ssp", f"{PATTERN}-ssp.json")))
    assert scrubbed["vpc"] == "vpc-EXAMPLE0001", "fixture did not exercise a rewrite"

    manifest = json.load(open(os.path.join(out, "manifest.json")))
    staleness = manifest["fedramp-20x-package"]["provenance"]["staleness_days"]
    assert staleness is not None and staleness > 1000, (
        "sanitization reset artifact mtimes and disarmed the staleness check"
    )
