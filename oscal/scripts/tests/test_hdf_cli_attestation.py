"""#225: verify SAF-attestation evidence survives HDF -> OSCAL SAR through the
MITRE `hdf` CLI (which replaced hdf_to_oscal.py in #284).

Integration test — shells out to the `hdf` CLI. Skips cleanly where the CLI is
absent (it's baked into the sparc-ci-runner image; may not be on a dev box).
The regression it guards: attestation narrative (explanation / frequency /
updated / updated_by) and the NIST control tag must reach the SAR observation,
so attestation-bound controls aren't silently dropped by the tooling swap.
"""
from __future__ import annotations

import json
import shutil
import subprocess

import pytest

HDF = shutil.which("hdf")
pytestmark = pytest.mark.skipif(HDF is None, reason="hdf CLI not on PATH (runner-only)")


@pytest.fixture(scope="module")
def sar(tmp_path_factory, fixtures_dir):
    out = tmp_path_factory.mktemp("sar") / "attest.sar.json"
    subprocess.run(
        [HDF, "convert", str(fixtures_dir / "hdf-attestation.json"),
         "--to", "oscal-sar", "--nist-rev", "5", "-o", str(out)],
        check=True, capture_output=True,
    )
    return json.loads(out.read_text())


def test_sar_is_assessment_results(sar):
    assert "assessment-results" in sar


def test_attestation_narrative_propagates(sar):
    blob = json.dumps(sar)
    # reviewer evidence fields must survive the conversion
    assert "Verified via IAM console" in blob   # explanation
    assert "annually" in blob                   # frequency
    assert "reviewer" in blob                    # updated_by


def test_nist_control_tag_applied(sar):
    # the awsconfig rule -> NIST mapping tags the SAR at 800-53 (AC-2 family)
    assert "AC-2" in json.dumps(sar)


def test_control_identity_preserved(sar):
    assert "access-keys-rotated" in json.dumps(sar)
