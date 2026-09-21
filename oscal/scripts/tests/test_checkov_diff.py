"""Tests for checkov_diff.py count-drift detection (#611/#518).

`count_drift` is the first gate metric that looks at per-resource counts rather
than check_id sets. It blocks deploys under --strict, so it gets coverage.
"""
import importlib.util
import sys
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "checkov_diff", Path(__file__).resolve().parents[1] / "checkov_diff.py"
)
checkov_diff = importlib.util.module_from_spec(_SPEC)
sys.modules["checkov_diff"] = checkov_diff
_SPEC.loader.exec_module(checkov_diff)

find_count_drift = checkov_diff.find_count_drift
evaluate_threshold = checkov_diff.evaluate_threshold


def _entry(count):
    return {"disposition": "accepted", "expected_count": count}


def _fails(n):
    return [{"resource": f"r{i}", "file_path": "f", "check_name": ""} for i in range(n)]


class TestFindCountDrift:
    def test_matching_counts_report_no_drift(self):
        baseline = {"CKV_AWS_1": _entry(3)}
        assert find_count_drift(baseline, {"CKV_AWS_1": _fails(3)}) == {}

    def test_growth_is_detected(self):
        """The CKV_AWS_356 case: 5 accepted, 8 live, invisible to set-based diffing."""
        baseline = {"CKV_AWS_356": _entry(5)}
        drift = find_count_drift(baseline, {"CKV_AWS_356": _fails(8)})
        assert drift == {"CKV_AWS_356": (5, 8, 3)}

    def test_narrowing_is_also_detected(self):
        """A negative delta means the acceptance is broader than reality (CKV_AWS_382)."""
        baseline = {"CKV_AWS_382": _entry(4)}
        drift = find_count_drift(baseline, {"CKV_AWS_382": _fails(3)})
        assert drift == {"CKV_AWS_382": (4, 3, -1)}

    def test_check_absent_from_scan_counts_as_zero(self):
        baseline = {"CKV_AWS_136": _entry(2)}
        drift = find_count_drift(baseline, {})
        assert drift == {"CKV_AWS_136": (2, 0, -2)}

    def test_expected_count_none_is_skipped_not_treated_as_zero(self):
        """Unset != 0. Treating it as 0 would flag every legacy row on first run."""
        baseline = {"CKV_AWS_1": {"disposition": "accepted", "expected_count": None}}
        assert find_count_drift(baseline, {"CKV_AWS_1": _fails(4)}) == {}

    def test_zero_expected_and_zero_actual_is_not_drift(self):
        baseline = {"CKV_DOCKER_2": _entry(0)}
        assert find_count_drift(baseline, {}) == {}

    def test_only_baselined_checks_are_considered(self):
        """A check absent from the baseline is New, not drift — no double-counting."""
        baseline = {"CKV_AWS_1": _entry(1)}
        drift = find_count_drift(baseline, {"CKV_AWS_1": _fails(1), "CKV_AWS_999": _fails(7)})
        assert drift == {}

    def test_multiple_drifts_all_reported(self):
        baseline = {"A": _entry(1), "B": _entry(2), "C": _entry(3)}
        drift = find_count_drift(baseline, {"A": _fails(2), "B": _fails(2), "C": _fails(1)})
        assert set(drift) == {"A", "C"}


class TestThresholdIntegration:
    BASE = {
        "min_pass_rate": 0, "max_new": -1, "max_regressions": -1,
        "max_untriaged": -1, "max_stale_reviews": -1, "max_total_failed": -1,
    }

    def _run(self, limit, drift):
        thresholds = dict(self.BASE, max_count_drift=limit)
        results = evaluate_threshold(thresholds, 100, 10, 0, 0, 0, 0, count_drift=drift)
        return next(r for r in results if r[0] == "Count Drift")

    def test_warn_only_passes_despite_drift(self):
        """Default (-1) must never block — this ships warn-only first."""
        metric, actual, limit, passed = self._run(-1, 5)
        assert (actual, limit, passed) == (5, -1, True)

    def test_strict_blocks_on_drift(self):
        _, actual, limit, passed = self._run(0, 1)
        assert (actual, limit, passed) == (1, 0, False)

    def test_strict_passes_when_clean(self):
        assert self._run(0, 0)[3] is True

    def test_metric_defaults_to_zero_when_not_supplied(self):
        """Back-compat: existing callers omit the argument."""
        thresholds = dict(self.BASE, max_count_drift=0)
        results = evaluate_threshold(thresholds, 100, 10, 0, 0, 0, 0)
        assert next(r for r in results if r[0] == "Count Drift")[3] is True


class TestLoadThreshold:
    def test_count_drift_defaults_to_warn_only_when_absent(self, tmp_path):
        """An older threshold.yml without the key must not start blocking."""
        p = tmp_path / "t.yml"
        p.write_text("compliance:\n  min_pass_rate: 80\nfindings:\n  new:\n    max: 0\n")
        assert checkov_diff.load_threshold(str(p), "ecs")["max_count_drift"] == -1

    def test_strict_layer_tightens_count_drift(self, tmp_path):
        p = tmp_path / "t.yml"
        p.write_text(
            "compliance:\n  min_pass_rate: 80\n"
            "findings:\n  count_drift:\n    max: -1\n"
            "strict:\n  findings:\n    count_drift:\n      max: 0\n"
        )
        assert checkov_diff.load_threshold(str(p), "ecs")["max_count_drift"] == -1
        assert checkov_diff.load_threshold(str(p), "ecs", strict=True)["max_count_drift"] == 0
