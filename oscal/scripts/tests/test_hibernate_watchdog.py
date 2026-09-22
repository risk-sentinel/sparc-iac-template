"""Tests for the hibernate/wake watchdog Lambda (#573).

Loads the handler from AWS/ECS/modules/lambda/scripts/hibernate_watchdog.py.
The Lambda's RS256 JWT signing is pure-stdlib (no cryptography/PyJWT) so the
safety-critical watchdog packages as a single .py; here we cross-verify that
signing against the `cryptography` library (a moto dependency, already present
in the test env) using keys in BOTH PKCS#1 and PKCS#8 form. No private key is
committed — keys are generated at test time.
"""

from __future__ import annotations

import base64
import importlib.util
import json
import sys
from datetime import datetime
from pathlib import Path

import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

REPO_ROOT = Path(__file__).resolve().parents[3]
HANDLER_SRC = REPO_ROOT / "AWS/ECS/modules/lambda/scripts/hibernate_watchdog.py"


@pytest.fixture(scope="session")
def wd():
    spec = importlib.util.spec_from_file_location("hibernate_watchdog", str(HANDLER_SRC))
    module = importlib.util.module_from_spec(spec)
    sys.modules["hibernate_watchdog"] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="session")
def rsa_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def _pem(key, fmt):
    return key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=fmt,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode()


def _b64url_decode(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


@pytest.mark.parametrize(
    "fmt",
    [serialization.PrivateFormat.TraditionalOpenSSL, serialization.PrivateFormat.PKCS8],
    ids=["pkcs1", "pkcs8"],
)
def test_key_parse_and_signature_valid(wd, rsa_key, fmt):
    """n/d parse correctly from both PEM formats and the signature verifies."""
    pem = _pem(rsa_key, fmt)
    n, d = wd._rsa_n_d_from_pem(pem)
    assert n == rsa_key.private_numbers().public_numbers.n
    assert d == rsa_key.private_numbers().d

    signing_input = b"eyJhbGciOiJSUzI1NiJ9.eyJpc3MiOiIxIn0"
    sig = wd._rs256_sign(signing_input, n, d)
    assert len(sig) == 256  # 2048-bit modulus
    # Raises InvalidSignature if wrong — the cross-check against a real crypto lib.
    rsa_key.public_key().verify(sig, signing_input, padding.PKCS1v15(), hashes.SHA256())


def test_make_app_jwt(wd, rsa_key):
    """Full JWT: correct structure, claims, and a signature over header.payload."""
    pem = _pem(rsa_key, serialization.PrivateFormat.PKCS8)
    token = wd._make_app_jwt("123456", pem)
    header_b64, payload_b64, sig_b64 = token.split(".")

    assert json.loads(_b64url_decode(header_b64)) == {"alg": "RS256", "typ": "JWT"}
    payload = json.loads(_b64url_decode(payload_b64))
    assert payload["iss"] == "123456"
    assert payload["exp"] - payload["iat"] == 600  # 10-minute lifetime

    signing_input = f"{header_b64}.{payload_b64}".encode()
    rsa_key.public_key().verify(
        _b64url_decode(sig_b64), signing_input, padding.PKCS1v15(), hashes.SHA256()
    )


@pytest.mark.parametrize(
    "hour,expected",
    [(0, "asleep"), (5, "asleep"), (6, "awake"), (12, "awake"), (20, "awake"), (21, "asleep"), (23, "asleep")],
)
def test_desired_state_boundaries(wd, hour, expected):
    """06:00-21:00 ET is awake; the edges (06:00 in, 21:00 out) are the ones
    the old fixed-UTC cron got wrong."""
    now_et = datetime(2026, 7, 25, hour, 0, tzinfo=wd.ET)
    assert wd._desired_state(now_et) == expected
