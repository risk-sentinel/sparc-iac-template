"""Unit tests for the AWS->NIST CDEF enrichment tooling (#287 commit 3):
build_cdef_mapping.py + extract_nist_r4_to_r5.py."""
from __future__ import annotations

import build_cdef_mapping as bm
import extract_nist_r4_to_r5 as ex


# ---- extract_nist_r4_to_r5 -------------------------------------------------

def test_norm_strips_zero_padding():
    assert ex._norm("AC-02") == "AC-2"
    assert ex._norm("AC-2(01)") == "AC-2(1)"
    assert ex._norm("SC-7") == "SC-7"


def test_incorporated_targets_drops_self_and_normalizes():
    # "AU-3(2) ... Withdrawn Incorporated into PL-9" with a zero-padded self-ref
    text = "Incorporated into PL-9  AU-03-2 details"
    out = ex._incorporated_targets(text, "AU-3(2)")
    assert "PL-9" in out
    assert "AU-3" not in out          # self-ref removed
    assert "AU-03" not in out         # normalized away


# ---- build_cdef_mapping ----------------------------------------------------

def test_norm_nist_keeps_part_letters():
    assert bm.norm_nist("AC-2(g)") == "AC-2(g)"
    assert bm.norm_nist("AC-02(1)") == "AC-2(1)"


def test_to_target_rev4_is_identity():
    out = bm.to_target_rev(["AC-2(1)", "SC-28", "AC-02"], 4, {})
    assert out == ["AC-2", "AC-2(1)", "SC-28"]


def test_to_target_rev5_redirects_withdrawn_only():
    cw = {"withdrawn_incorporated": {"SA-13": ["SA-8", "PL-8"], "IA-5(4)": ["IA-5"]}}
    # SC-28 carries over identically; SA-13 + IA-5(4) redirect
    out = bm.to_target_rev(["SC-28", "SA-13", "IA-5(4)"], 5, cw)
    assert "SC-28" in out
    assert "SA-8" in out and "PL-8" in out and "SA-13" not in out
    assert "IA-5" in out and "IA-5(4)" not in out


def test_to_target_rev5_part_letter_base_redirect():
    cw = {"withdrawn_incorporated": {"AC-2": ["AC-2"]}}
    # AC-2(g) base AC-2 present in redirects -> resolves via base
    out = bm.to_target_rev(["AC-2(g)"], 5, cw)
    assert out == ["AC-2"]


def test_deployed_config_rules_parses_state():
    state = {"resources": [{
        "mode": "managed", "type": "aws_config_config_rule",
        "instances": [{"attributes": {
            "name": "s3-bucket-ssl-requests-only",
            "source": [{"source_identifier": "S3_BUCKET_SSL_REQUESTS_ONLY"}],
        }}],
    }, {"mode": "data", "type": "aws_caller_identity", "instances": [{}]}]}
    assert bm.deployed_config_rules([state]) == [
        ("s3-bucket-ssl-requests-only", "S3_BUCKET_SSL_REQUESTS_ONLY")]


def test_build_maps_shape_and_unmapped():
    by_src = {"S3_BUCKET_SSL_REQUESTS_ONLY": "SC-13|SC-8"}
    by_name = {}
    rules = [("s3-bucket-ssl-requests-only", "S3_BUCKET_SSL_REQUESTS_ONLY"),
             ("mystery-rule", "MYSTERY")]
    maps, unmapped, stats = bm.build_maps(rules, by_src, by_name, 4, {})
    assert unmapped == ["mystery-rule"]
    assert len(maps) == 1
    m = maps[0]
    assert m["relationship"] == bm.RELATIONSHIP
    assert m["sources"][0]["id-ref"] == "s3-bucket-ssl-requests-only"
    assert {t["id-ref"] for t in m["targets"]} == {"sc-13", "sc-8"}  # lowercased
    assert stats["distinct_nist_controls"] == 2


def test_build_collection_has_all_required_fields():
    coll = bm.build_collection([], 5, "t", "2026-07-27T00:00:00Z", ["p"])
    mc = coll["mapping-collection"]
    for key in ("uuid", "metadata", "provenance", "mappings"):
        assert key in mc
    for key in ("title", "last-modified", "version", "oscal-version"):
        assert key in mc["metadata"]
    assert mc["metadata"]["oscal-version"] == "1.2.1"
    for key in ("method", "matching-rationale", "status", "mapping-description"):
        assert key in mc["provenance"]
