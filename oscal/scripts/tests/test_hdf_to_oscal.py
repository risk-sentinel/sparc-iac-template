"""Tests for hdf_to_oscal.py — focus on inheritance semantics added in #187."""

from __future__ import annotations

import pytest

from hdf_to_oscal import (
    AWS_ATTESTATION_CATALOG,
    LEGAL_IMPLEMENTATION_STATUS,
    SPARC_VALIDATE_PROP_NS,
    _detect_component,
    _read_implementation_status,
    convert_hdf_to_oscal,
)


# --- _read_implementation_status ----------------------------------------


def test_reader_returns_none_when_tag_absent():
    control = {"tags": {"nist": ["ac-3"]}}
    assert _read_implementation_status(control) == (None, None, [])


def test_reader_handles_missing_tags_dict():
    control = {}
    assert _read_implementation_status(control) == (None, None, [])


def test_reader_returns_legal_enum():
    control = {"tags": {"implementation_status": "implemented"}}
    status, inherited_from, refs = _read_implementation_status(control)
    assert status == "implemented"
    assert inherited_from is None
    assert refs == []


def test_reader_returns_inherited_with_metadata():
    control = {
        "tags": {
            "implementation_status": "inherited",
            "inherited_from": "aws-shared-responsibility",
            "attestation_references": ["AWS SOC 2 Type II", "AWS FedRAMP High"],
        }
    }
    status, inherited_from, refs = _read_implementation_status(control)
    assert status == "inherited"
    assert inherited_from == "aws-shared-responsibility"
    assert refs == ["AWS SOC 2 Type II", "AWS FedRAMP High"]


def test_reader_drops_unknown_status_value():
    """Unknown statuses are ignored rather than emitted (avoids invalid OSCAL)."""
    control = {"tags": {"implementation_status": "magic-status-not-real"}}
    assert _read_implementation_status(control) == (None, None, [])


def test_reader_strips_and_lowercases_status():
    control = {"tags": {"implementation_status": "  Implemented  "}}
    status, _, _ = _read_implementation_status(control)
    assert status == "implemented"


def test_reader_filters_blank_attestation_refs():
    control = {
        "tags": {
            "implementation_status": "inherited",
            "attestation_references": ["AWS SOC 2 Type II", "", "  ", 123, None],
        }
    }
    _, _, refs = _read_implementation_status(control)
    assert refs == ["AWS SOC 2 Type II"]


# --- convert_hdf_to_oscal: inheritance integration -------------------------


def _result(sar):
    return sar["assessment-results"]["results"][0]


def _findings_by_id(sar):
    return {f["title"]: f for f in _result(sar)["findings"]}


def _props_map(props):
    return {(p.get("ns"), p["name"]): p["value"] for p in props or []}


def test_inherited_emits_local_definitions_and_back_matter(org_config, load_fixture):
    hdf = load_fixture("hdf-inherited")
    sar, _, _ = convert_hdf_to_oscal(hdf, "cis-postgresql", "Test System", org_config)
    result = _result(sar)

    # local-definitions populated with the AWS provider component.
    ld = result["local-definitions"]
    assert len(ld["components"]) == 1
    assert ld["components"][0]["title"].startswith("AWS")
    assert ld["components"][0]["type"] == "service"

    # control-implementations -> implemented-requirements -> by-components -> inherited
    cis = ld["control-implementations"]
    assert len(cis) == 1
    irs = cis[0]["implemented-requirements"]
    assert len(irs) == 1
    assert irs[0]["control-id"] == "pe-2"
    by_comps = irs[0]["by-components"]
    assert len(by_comps) == 1
    assert by_comps[0]["component-uuid"] == ld["components"][0]["uuid"]
    inherited_blocks = by_comps[0]["inherited"]
    assert len(inherited_blocks) == 1
    # Implementation-status state is "implemented" on the operator side
    # (CSP satisfies the responsibility); the inheritance semantic lives in
    # the inherited[] block, not in an enum value of "inherited".
    assert by_comps[0]["implementation-status"]["state"] == "implemented"

    # Back-matter resources cover all four cited attestations.
    bm = sar["assessment-results"]["back-matter"]
    titles = {r["title"] for r in bm["resources"]}
    expected = {AWS_ATTESTATION_CATALOG[name]["title"]
                for name in AWS_ATTESTATION_CATALOG.keys()}
    assert titles == expected

    # inherited[] block references each attestation by stable UUID via #anchors.
    links = inherited_blocks[0]["links"]
    assert len(links) == 4
    for link in links:
        assert link["href"].startswith("#")
        assert link["rel"] == "attestation"

    # Finding also carries a custom prop so consumers that don't traverse
    # local-definitions still see the inheritance signal.
    finding = result["findings"][0]
    props = _props_map(finding.get("props"))
    assert props.get((SPARC_VALIDATE_PROP_NS, "implementation-status")) == "inherited"


def test_mixed_statuses_attach_props_and_only_inherited_uses_local_defs(org_config, load_fixture):
    hdf = load_fixture("hdf-mixed")
    sar, _, _ = convert_hdf_to_oscal(hdf, "cis-postgresql", "Test System", org_config)
    result = _result(sar)
    findings_by_title = _findings_by_id(sar)

    # Each non-inherited legal status surfaces as a custom prop on the finding.
    for status in LEGAL_IMPLEMENTATION_STATUS:
        # Only check the ones that exist in the fixture.
        title_map = {
            "implemented": "Implemented control",
            "alternative": "Alternative-implementation control",
            "not-applicable": "Not-applicable control",
            "planned": "Planned control (pending)",
        }
        if status not in title_map:
            continue
        finding = findings_by_title[title_map[status]]
        props = _props_map(finding.get("props"))
        assert props.get((SPARC_VALIDATE_PROP_NS, "implementation-status")) == status

    # Tag-absent finding has no implementation-status prop — pre-#187 behaviour.
    plain = findings_by_title["Control with no implementation_status tag"]
    plain_props = _props_map(plain.get("props"))
    assert (SPARC_VALIDATE_PROP_NS, "implementation-status") not in plain_props

    # Inherited control populates local-definitions with the single attestation cited.
    ld = result["local-definitions"]
    assert len(ld["control-implementations"][0]["implemented-requirements"]) == 1
    bm_titles = {r["title"] for r in sar["assessment-results"]["back-matter"]["resources"]}
    assert bm_titles == {AWS_ATTESTATION_CATALOG["AWS SOC 2 Type II"]["title"]}


def test_no_inheritance_tags_produces_no_local_defs_or_back_matter(org_config, load_fixture):
    """Regression: HDFs from tools that don't carry the new tags must not gain
    local-definitions or back-matter sections — output stays byte-identical to
    pre-#187 behaviour for those callers."""
    hdf = load_fixture("hdf-no-tags")
    sar, _, _ = convert_hdf_to_oscal(hdf, "checkov", "Test System", org_config)
    result = _result(sar)
    assert "local-definitions" not in result
    assert "back-matter" not in sar["assessment-results"]
    # No finding has an implementation-status prop either.
    for finding in result["findings"]:
        props = _props_map(finding.get("props"))
        assert (SPARC_VALIDATE_PROP_NS, "implementation-status") not in props


def test_unknown_status_falls_back_to_no_metadata(org_config):
    hdf = {
        "profiles": [
            {
                "name": "test",
                "controls": [
                    {
                        "id": "x-1",
                        "title": "weird status",
                        "tags": {"nist": ["ac-3"], "implementation_status": "wat"},
                        "results": [{"status": "passed"}],
                    }
                ],
            }
        ]
    }
    sar, _, _ = convert_hdf_to_oscal(hdf, "test", "Test System", org_config)
    result = _result(sar)
    assert "local-definitions" not in result
    assert "back-matter" not in sar["assessment-results"]
    finding = result["findings"][0]
    props = _props_map(finding.get("props"))
    assert (SPARC_VALIDATE_PROP_NS, "implementation-status") not in props


def test_attestation_uuids_stable_across_runs(org_config, load_fixture):
    """Re-running the converter on the same HDF must produce the same
    attestation resource UUIDs — otherwise document UUIDs churn on every run."""
    hdf = load_fixture("hdf-inherited")
    sar1, _, _ = convert_hdf_to_oscal(hdf, "cis-postgresql", "Test System", org_config)
    sar2, _, _ = convert_hdf_to_oscal(hdf, "cis-postgresql", "Test System", org_config)
    uuids1 = sorted(r["uuid"] for r in sar1["assessment-results"]["back-matter"]["resources"])
    uuids2 = sorted(r["uuid"] for r in sar2["assessment-results"]["back-matter"]["resources"])
    assert uuids1 == uuids2


# --- _detect_component (sparc-iac#198) -----------------------------------


def test_detect_component_reads_profile_name(load_fixture):
    """The component label is the literal profile name from the HDF."""
    hdf = load_fixture("hdf-inherited")
    assert _detect_component(hdf) == "cis-postgresql"


def test_detect_component_returns_none_for_tool_style_hdf():
    """Tool-produced HDFs (Brakeman, CodeQL, Trivy …) often have no profile
    name — the caller falls back to detect_tool() in that path."""
    hdf = {"profiles": []}
    assert _detect_component(hdf) is None
    hdf_no_profiles_key = {}
    assert _detect_component(hdf_no_profiles_key) is None


def test_detect_component_handles_blank_or_non_string_name():
    """Defensive: blank / whitespace / non-string profile name returns None."""
    assert _detect_component({"profiles": [{"name": ""}]}) is None
    assert _detect_component({"profiles": [{"name": "   "}]}) is None
    assert _detect_component({"profiles": [{"name": None}]}) is None
    assert _detect_component({"profiles": [{"name": 123}]}) is None
    assert _detect_component({"profiles": [{}]}) is None


def test_detect_component_strips_surrounding_whitespace():
    assert _detect_component({"profiles": [{"name": "  cis-nginx  "}]}) == "cis-nginx"


# --- (component, control_id) keying robust to control-ID format (#198) --


def test_keying_robust_to_saf_c_format_control_ids(org_config, load_fixture):
    """Forward-compat with sparc-validate#39: the converter must produce a
    valid SAR for HDFs whose control IDs use SAF's ``C-N.N.N.N`` shape, not
    the current ``cis-X-N.M`` shape. Control IDs flow through opaquely; the
    structural keying is ``(component, control_id)``."""
    hdf = load_fixture("hdf-cis-postgresql-saf-format")
    sar, passed, failed = convert_hdf_to_oscal(hdf, "cis-postgresql", "Test System", org_config)
    result = _result(sar)

    # Three controls in the fixture: C-2.6 (passed), C-3.1.4 (failed), C-1.1 (skipped/inherited).
    # Skipped is treated as not-pass (failed in counts) by the existing converter.
    assert passed + failed == 3

    # Findings carry the C-N.N.N.N IDs unchanged in titles / descriptions.
    finding_titles = {f["title"] for f in result["findings"]}
    assert "Ensure PostgreSQL log destination is set" in finding_titles

    # Inherited path still attaches local-definitions + back-matter for the
    # C-1.1 control. NIST mapping (pe-2) reads from the tags, not the ID.
    ld = result["local-definitions"]
    assert ld["control-implementations"][0]["implemented-requirements"][0]["control-id"] == "pe-2"
    bm_titles = {r["title"] for r in sar["assessment-results"]["back-matter"]["resources"]}
    assert bm_titles == {AWS_ATTESTATION_CATALOG["AWS SOC 2 Type II"]["title"]}


def test_keying_uuids_stable_for_saf_format(org_config, load_fixture):
    """Determinism applies regardless of the control-ID format."""
    hdf = load_fixture("hdf-cis-postgresql-saf-format")
    sar1, _, _ = convert_hdf_to_oscal(hdf, "cis-postgresql", "Test System", org_config)
    sar2, _, _ = convert_hdf_to_oscal(hdf, "cis-postgresql", "Test System", org_config)
    obs1 = sorted(o["uuid"] for o in _result(sar1)["observations"])
    obs2 = sorted(o["uuid"] for o in _result(sar2)["observations"])
    assert obs1 == obs2
    fnd1 = sorted(f["uuid"] for f in _result(sar1)["findings"])
    fnd2 = sorted(f["uuid"] for f in _result(sar2)["findings"])
    assert fnd1 == fnd2


def test_keying_distinguishes_components_with_same_control_id(org_config):
    """Two different components (e.g. cis-aws-compute and cis-docker) may
    legitimately ship a control with the same ID (e.g. ``C-3.1`` in both).
    The ``(component, control_id)`` keying must produce distinct stable UUIDs
    for those two findings — otherwise the OSCAL emitter collapses them."""
    hdf_template = {
        "profiles": [
            {
                "name": "placeholder",
                "controls": [
                    {
                        "id": "C-3.1",
                        "title": "Generic check",
                        "desc": "Same control ID, different components.",
                        "tags": {"nist": ["cm-7"]},
                        "results": [{"status": "passed"}],
                    }
                ],
            }
        ]
    }
    sar_compute, _, _ = convert_hdf_to_oscal(hdf_template, "cis-aws-compute", "Sys", org_config)
    sar_docker, _, _ = convert_hdf_to_oscal(hdf_template, "cis-docker", "Sys", org_config)

    finding_compute = _result(sar_compute)["findings"][0]
    finding_docker = _result(sar_docker)["findings"][0]
    assert finding_compute["uuid"] != finding_docker["uuid"]

    obs_compute = _result(sar_compute)["observations"][0]
    obs_docker = _result(sar_docker)["observations"][0]
    assert obs_compute["uuid"] != obs_docker["uuid"]
