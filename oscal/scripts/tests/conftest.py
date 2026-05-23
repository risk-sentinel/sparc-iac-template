"""pytest configuration for oscal/scripts tests.

Adds the parent directory to sys.path so tests can `from hdf_to_oscal import ...`
without needing the script directory on PYTHONPATH explicitly.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

SCRIPTS_DIR = Path(__file__).resolve().parent.parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"


@pytest.fixture(scope="session")
def fixtures_dir() -> Path:
    return FIXTURES_DIR


@pytest.fixture(scope="session")
def org_config():
    """Minimal org_config for tests — uses the repo's organization_variables.yml.

    stable_uuid needs a config; we load the real one so produced UUIDs are
    deterministic with the rest of the pipeline.
    """
    from org_config import load_config

    repo_root = SCRIPTS_DIR.parent.parent
    config_path = repo_root / "organization_variables.yml"
    return load_config(str(config_path))


@pytest.fixture(scope="session")
def load_fixture():
    """Return a callable that loads a JSON fixture by basename (no extension)."""

    def _load(name: str) -> dict:
        path = FIXTURES_DIR / f"{name}.json"
        with path.open() as f:
            return json.load(f)

    return _load
