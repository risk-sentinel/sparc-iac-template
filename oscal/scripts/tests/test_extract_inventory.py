"""Tests for extract_inventory.py (#632).

The point of these tests is the security filter. Terraform state holds plaintext
secrets, so the assertion that matters is not "the inventory has the right
shape" — it is "no secret survives extraction, including ones nobody enumerated".
"""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import extract_inventory as ei  # noqa: E402


SECRET_VALUES = [
    "hunter2-actual-db-password",
    "-----BEGIN RSA PRIVATE KEY-----",
    "postgres://user:pa55w0rd@host:5432/db",
    "ghp_realLookingGitHubTokenValue",
    "AKIAEXAMPLE0001",
]


def _state_with_secrets():
    """A state document shaped like the real one, seeded with secrets in the
    places Terraform actually puts them."""
    return {
        "values": {
            "root_module": {
                "resources": [
                    {
                        "mode": "managed",
                        "type": "random_password",
                        "name": "db",
                        "address": "random_password.db",
                        "values": {"id": "rp-1", "result": SECRET_VALUES[0], "length": 32},
                    },
                    {
                        "mode": "data",
                        "type": "aws_iam_policy_document",
                        "name": "ignored",
                        "address": "data.aws_iam_policy_document.ignored",
                        "values": {"json": "{}", "id": "d-1"},
                    },
                ],
                "child_modules": [
                    {
                        "resources": [
                            {
                                "mode": "managed",
                                "type": "aws_secretsmanager_secret_version",
                                "name": "app",
                                "address": "module.secrets.aws_secretsmanager_secret_version.app",
                                "values": {
                                    "id": "sv-1",
                                    "arn": "arn:aws:secretsmanager:us-east-1:1:secret:app",
                                    "secret_string": SECRET_VALUES[2],
                                },
                            },
                            {
                                "mode": "managed",
                                "type": "aws_db_instance",
                                "name": "main",
                                "address": "module.rds.aws_db_instance.main",
                                "values": {
                                    "id": "db-1",
                                    "arn": "arn:aws:rds:us-east-1:1:db:example",
                                    "engine": "postgres",
                                    "engine_version": "16.4",
                                    "password": SECRET_VALUES[0],
                                    "master_user_secret": {"secret_arn": "arn:x"},
                                },
                            },
                            {
                                "mode": "managed",
                                "type": "aws_iam_role",
                                "name": "emit",
                                "address": 'module.iam.aws_iam_role.profile_emit["cis-docker-baseline"]',
                                "values": {
                                    "id": "example-cis-docker-baseline-emit",
                                    "arn": "arn:aws:iam::1:role/example-cis-docker-baseline-emit",
                                    "name": "example-cis-docker-baseline-emit",
                                    "assume_role_policy": "{...trust doc...}",
                                },
                            },
                        ],
                        "child_modules": [],
                    }
                ],
            }
        }
    }


def test_no_secret_value_survives_extraction():
    """The load-bearing test. Every secret seeded into state must be absent from
    the serialized inventory — not redacted, absent."""
    records = ei.extract(_state_with_secrets())
    blob = json.dumps(records)
    for secret in SECRET_VALUES:
        assert secret not in blob, f"secret leaked into inventory: {secret[:20]}"


def test_unknown_attributes_are_dropped_not_kept():
    """An attribute nobody enumerated must be dropped by default. This is the
    difference between an allowlist and a denylist, and the reason the filter is
    written as an allowlist."""
    state = {
        "values": {
            "root_module": {
                "resources": [
                    {
                        "mode": "managed",
                        "type": "aws_thing",
                        "name": "t",
                        "address": "aws_thing.t",
                        "values": {
                            "id": "t-1",
                            "some_future_attribute_nobody_listed": "sensitive-by-accident",
                        },
                    }
                ],
                "child_modules": [],
            }
        }
    }
    records = ei.extract(state)
    assert records[0]["attributes"] == {"id": "t-1"}
    assert "sensitive-by-accident" not in json.dumps(records)


def test_forbidden_pattern_blocks_an_allowlisted_key(monkeypatch):
    """Second gate: if a sensitive key is ever added to SAFE_ATTRS by mistake,
    FORBIDDEN_PATTERN still blocks it."""
    monkeypatch.setattr(ei, "SAFE_ATTRS", ei.SAFE_ATTRS | {"secret_string"})
    out = ei.safe_attributes({"id": "x", "secret_string": SECRET_VALUES[2]})
    assert out == {"id": "x"}


def test_oversized_values_are_dropped():
    """A large document riding through on an allowlisted key is dropped."""
    out = ei.safe_attributes({"name": "n" * 300, "id": "ok"})
    assert out == {"id": "ok"}


def test_data_sources_are_excluded():
    """Data sources describe intent, not deployed state."""
    records = ei.extract(_state_with_secrets())
    assert all(r["type"] != "aws_iam_policy_document" for r in records)


def test_child_modules_are_walked():
    """Most real resources live in child modules; missing them would produce a
    plausible-looking but near-empty inventory."""
    records = ei.extract(_state_with_secrets())
    types = {r["type"] for r in records}
    assert "aws_db_instance" in types
    assert "aws_iam_role" in types


def test_records_without_an_identifier_are_skipped():
    state = {
        "values": {
            "root_module": {
                "resources": [
                    {"mode": "managed", "type": "aws_x", "name": "x",
                     "address": "aws_x.x", "values": {"length": 4}}
                ],
                "child_modules": [],
            }
        }
    }
    assert ei.extract(state) == []


def test_identifier_prefers_arn():
    records = ei.extract(_state_with_secrets())
    role = next(r for r in records if r["type"] == "aws_iam_role")
    assert role["identifier"].startswith("arn:aws:iam::")
