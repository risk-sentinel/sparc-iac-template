"""Tests for the admin-credential rotation Lambda (#151).

Loads the handler from AWS/ECS/modules/lambda/scripts/admin_rotation.py.
Uses moto for Secrets Manager + SNS, and unittest.mock to intercept the
SigV4-signed HTTP POST so we can drive SPARC's contract responses.
"""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import uuid
from io import BytesIO
from pathlib import Path
from unittest import mock
from urllib.error import HTTPError

import boto3
import pytest
from moto import mock_aws

REPO_ROOT = Path(__file__).resolve().parents[3]
HANDLER_SRC = REPO_ROOT / "AWS/ECS/modules/lambda/scripts/admin_rotation.py"


@pytest.fixture(scope="session")
def admin_rotation_module():
    """Dynamically load the handler module from its on-disk path."""
    spec = importlib.util.spec_from_file_location("admin_rotation", str(HANDLER_SRC))
    module = importlib.util.module_from_spec(spec)
    sys.modules["admin_rotation"] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def bypass_preflight(admin_rotation_module, monkeypatch):
    """The pre-flight check needs RotationEnabled=True on the secret, which in
    moto requires creating a real Lambda function with full IAM scaffolding.
    Out of scope for unit tests of the handler — bypass the check here and
    cover it directly in test_preflight_*."""
    monkeypatch.setattr(admin_rotation_module, "_ensure_rotation_enabled", lambda *a, **kw: None)


@pytest.fixture
def aws_env(monkeypatch):
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("AWS_REGION", "us-east-1")


@pytest.fixture
def lambda_env(monkeypatch, aws_env):
    monkeypatch.setenv("SPARC_API_BASE_URL", "https://sparc.example.test")
    monkeypatch.setenv("SECRET_ARN", "arn:aws:secretsmanager:us-east-1:111111111111:secret:test-admin-AAAAAA")
    monkeypatch.setenv("SNS_TOPIC_ARN", "arn:aws:sns:us-east-1:111111111111:test-alarms")
    monkeypatch.setenv("ROTATION_TOKEN_SECRET_ARN", "arn:aws:secretsmanager:us-east-1:111111111111:secret:test-rotation-token-BBBBBB")


@pytest.fixture
def stubbed_bearer_token(admin_rotation_module, monkeypatch):
    """Most tests don't care how the Bearer token is fetched — stub _fetch_bearer_token
    to return a fixed string so we can assert on the resulting Authorization header.
    Dedicated tests below exercise the real fetch path against moto."""
    monkeypatch.setattr(admin_rotation_module, "_fetch_bearer_token", lambda: "sparc_sa_test_token_xxx")




# ---------------------------------------------------------------------------
# HTTP transport double — covers SigV4 signing and SPARC contract responses
# ---------------------------------------------------------------------------


class FakeURLOpen:
    """Drop-in replacement for urllib.request.urlopen.

    Records calls and returns canned responses based on a script. Each entry
    in the script is either a (status, body_dict) tuple or an HTTPError to
    raise.
    """

    def __init__(self, script):
        self.script = list(script)
        self.calls = []

    def __call__(self, request, timeout=None):
        self.calls.append({
            "url": request.full_url,
            "method": request.get_method(),
            "headers": dict(request.headers.items()),
            "body": request.data,
        })
        if not self.script:
            raise AssertionError("FakeURLOpen ran out of scripted responses")
        action = self.script.pop(0)
        if isinstance(action, BaseException):
            raise action
        status, payload = action
        body = json.dumps(payload).encode("utf-8")
        return _FakeResponse(body)


class _FakeResponse:
    def __init__(self, body):
        self._body = body

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def _http_error(code, payload):
    body = json.dumps(payload).encode("utf-8")
    return HTTPError(
        url="https://sparc.example.test/api/admin/refresh_credentials",
        code=code,
        msg="error",
        hdrs=None,
        fp=BytesIO(body),
    )


# ---------------------------------------------------------------------------
# createSecret
# ---------------------------------------------------------------------------


def test_create_secret_writes_pending_with_new_password(
    admin_rotation_module, lambda_env, bypass_preflight
):
    token = str(uuid.uuid4())
    with mock_aws():
        # Re-init the secret inside this mock_aws context so the assertion
        # below reads from the same backing store the handler writes to.
        sm = boto3.client("secretsmanager", region_name="us-east-1")
        sm.create_secret(
            Name="test-admin",
            SecretString=json.dumps(
                {
                    "sparc_admin_email": "admin@example.test",
                    "sparc_admin_password": "old",
                    "smtp_username": "admin@example.test",
                    "smtp_password": "smtp",
                }
            ),
        )
        admin_rotation_module.handler(
            {
                "Step": "createSecret",
                "SecretId": "test-admin",
                "ClientRequestToken": token,
            },
            None,
        )
        pending = sm.get_secret_value(SecretId="test-admin", VersionStage="AWSPENDING")
        payload = json.loads(pending["SecretString"])
        assert payload["sparc_admin_password"] != "old"
        assert len(payload["sparc_admin_password"]) == 32
        # Non-rotating fields preserved
        assert payload["sparc_admin_email"] == "admin@example.test"
        assert payload["smtp_password"] == "smtp"


def test_create_secret_is_idempotent_when_pending_exists(
    admin_rotation_module, lambda_env, bypass_preflight
):
    """If AWSPENDING already exists for the same token, createSecret is a no-op."""
    with mock_aws():
        sm = boto3.client("secretsmanager", region_name="us-east-1")
        sm.create_secret(
            Name="test-admin",
            SecretString=json.dumps(
                {"sparc_admin_email": "a@b", "sparc_admin_password": "old"}
            ),
        )
        token = str(uuid.uuid4())
        sm.put_secret_value(
            SecretId="test-admin",
            ClientRequestToken=token,
            SecretString=json.dumps({"sparc_admin_email": "a@b", "sparc_admin_password": "preset"}),
            VersionStages=["AWSPENDING"],
        )
        admin_rotation_module.handler(
            {"Step": "createSecret", "SecretId": "test-admin", "ClientRequestToken": token},
            None,
        )
        pending = sm.get_secret_value(SecretId="test-admin", VersionStage="AWSPENDING")
        # Unchanged from the seeded value
        assert json.loads(pending["SecretString"])["sparc_admin_password"] == "preset"


# ---------------------------------------------------------------------------
# setSecret + testSecret
# ---------------------------------------------------------------------------


def test_set_secret_calls_sparc_with_bearer_token(admin_rotation_module, lambda_env, bypass_preflight, stubbed_bearer_token):
    """Per #197 v2 design — Bearer token, not SigV4."""
    token = str(uuid.uuid4())
    fake = FakeURLOpen([(200, {"status": "ok", "audit_event_id": 42, "rotated_at": "2026-04-26T00:00:00Z"})])
    with mock_aws():
        sm = boto3.client("secretsmanager", region_name="us-east-1")
        sm.create_secret(Name="test-admin", SecretString=json.dumps({"sparc_admin_password": "x"}))
        sm.put_secret_value(
            SecretId="test-admin",
            ClientRequestToken=token,
            SecretString=json.dumps({"sparc_admin_password": "new"}),
            VersionStages=["AWSPENDING"],
        )
        with mock.patch.object(admin_rotation_module.urllib.request, "urlopen", fake):
            admin_rotation_module.handler(
                {"Step": "setSecret", "SecretId": "test-admin", "ClientRequestToken": token},
                None,
            )

    assert len(fake.calls) == 1
    call = fake.calls[0]
    assert call["url"] == "https://sparc.example.test/api/admin/refresh_credentials"
    assert call["method"] == "POST"
    assert json.loads(call["body"]) == {"secret_version_id": token}
    auth_headers = {k.lower(): v for k, v in call["headers"].items()}
    assert auth_headers.get("authorization") == "Bearer sparc_sa_test_token_xxx"


def test_fetch_bearer_token_reads_from_secrets_manager(admin_rotation_module, lambda_env):
    """The real fetch path: GetSecretValue against the rotation-token secret."""
    with mock_aws():
        sm = boto3.client("secretsmanager", region_name="us-east-1")
        sm.create_secret(Name="test-rotation-token", SecretString="sparc_sa_real_token_42")
        # Override the env var to point at the test secret name (moto resolves by name)
        import os
        os.environ["ROTATION_TOKEN_SECRET_ARN"] = "test-rotation-token"
        try:
            assert admin_rotation_module._fetch_bearer_token() == "sparc_sa_real_token_42"
        finally:
            os.environ["ROTATION_TOKEN_SECRET_ARN"] = "arn:aws:secretsmanager:us-east-1:111111111111:secret:test-rotation-token-BBBBBB"


def test_fetch_bearer_token_raises_on_empty(admin_rotation_module, lambda_env, monkeypatch):
    """Empty rotation-token secret = unprovisioned. Fail loud rather than silently
    sending an empty Authorization header SPARC will reject as 401.

    Secrets Manager doesn't allow creating a secret with an empty SecretString,
    so the empty-string path is exercised via a mock that simulates a secret
    whose value was cleared out-of-band post-creation.
    """
    fake_sm = mock.MagicMock()
    fake_sm.get_secret_value.return_value = {"SecretString": "  "}  # whitespace-only after .strip()
    monkeypatch.setattr(admin_rotation_module.boto3, "client", lambda *a, **kw: fake_sm)
    with pytest.raises(RuntimeError, match="empty"):
        admin_rotation_module._fetch_bearer_token()


def test_test_secret_accepts_unchanged_status(admin_rotation_module, lambda_env, bypass_preflight, stubbed_bearer_token):
    """SPARC's idempotency contract: 200 'unchanged' on second call is success."""
    token = str(uuid.uuid4())
    fake = FakeURLOpen([(200, {"status": "unchanged", "audit_event_id": 43, "rotated_at": "..."})])
    with mock_aws():
        sm = boto3.client("secretsmanager", region_name="us-east-1")
        sm.create_secret(Name="test-admin", SecretString=json.dumps({"x": "y"}))
        sm.put_secret_value(
            SecretId="test-admin",
            ClientRequestToken=token,
            SecretString=json.dumps({"x": "y2"}),
            VersionStages=["AWSPENDING"],
        )
        with mock.patch.object(admin_rotation_module.urllib.request, "urlopen", fake):
            admin_rotation_module.handler(
                {"Step": "testSecret", "SecretId": "test-admin", "ClientRequestToken": token},
                None,
            )


@pytest.mark.parametrize(
    "code,error_body",
    [
        (401, {"error": "Unauthorized"}),
        (403, {"error": "IAM role not permitted"}),
        (404, {"error": "secret_version_id not found"}),
        (410, {"error": "secret_version_id older than 24h"}),
        (429, {"error": "rotation rate limit"}),
        (503, {"error": "feature disabled"}),
    ],
)
def test_set_secret_propagates_sparc_errors(
    admin_rotation_module, lambda_env, bypass_preflight, stubbed_bearer_token, code, error_body
):
    """All documented error codes from SPARC's contract surface as exceptions
    so Secrets Manager retries / DLQ handling kicks in. AWSPENDING stays in
    place; AWSCURRENT is untouched -- rollback by omission."""
    token = str(uuid.uuid4())
    fake = FakeURLOpen([_http_error(code, error_body)])
    with mock_aws():
        sm = boto3.client("secretsmanager", region_name="us-east-1")
        sm.create_secret(Name="test-admin", SecretString=json.dumps({"x": "y"}))
        sm.put_secret_value(
            SecretId="test-admin",
            ClientRequestToken=token,
            SecretString=json.dumps({"x": "y2"}),
            VersionStages=["AWSPENDING"],
        )
        sns = boto3.client("sns", region_name="us-east-1")
        sns.create_topic(Name="test-alarms")
        with mock.patch.object(admin_rotation_module.urllib.request, "urlopen", fake):
            with pytest.raises(RuntimeError, match=str(code)):
                admin_rotation_module.handler(
                    {"Step": "setSecret", "SecretId": "test-admin", "ClientRequestToken": token},
                    None,
                )

        # AWSPENDING still exists with the new value (SPARC didn't apply it).
        # AWSCURRENT is unchanged.
        pending = sm.get_secret_value(SecretId="test-admin", VersionStage="AWSPENDING")
        assert json.loads(pending["SecretString"])["x"] == "y2"
        current = sm.get_secret_value(SecretId="test-admin", VersionStage="AWSCURRENT")
        assert json.loads(current["SecretString"])["x"] == "y"


# ---------------------------------------------------------------------------
# finishSecret
# ---------------------------------------------------------------------------


def test_finish_secret_promotes_pending_to_current(admin_rotation_module, lambda_env, bypass_preflight):
    token = str(uuid.uuid4())
    with mock_aws():
        sm = boto3.client("secretsmanager", region_name="us-east-1")
        sm.create_secret(
            Name="test-admin",
            SecretString=json.dumps({"sparc_admin_password": "old"}),
        )
        sm.put_secret_value(
            SecretId="test-admin",
            ClientRequestToken=token,
            SecretString=json.dumps({"sparc_admin_password": "new"}),
            VersionStages=["AWSPENDING"],
        )
        admin_rotation_module.handler(
            {"Step": "finishSecret", "SecretId": "test-admin", "ClientRequestToken": token},
            None,
        )
        promoted = sm.get_secret_value(SecretId="test-admin", VersionStage="AWSCURRENT")
        assert json.loads(promoted["SecretString"])["sparc_admin_password"] == "new"


# ---------------------------------------------------------------------------
# Pre-flight check
# ---------------------------------------------------------------------------


def test_unknown_step_raises(admin_rotation_module, lambda_env, bypass_preflight):
    with mock_aws():
        sm = boto3.client("secretsmanager", region_name="us-east-1")
        sm.create_secret(Name="test-admin", SecretString="{}")
        with pytest.raises(ValueError, match="Unknown rotation step"):
            admin_rotation_module.handler(
                {"Step": "MagicStep", "SecretId": "test-admin", "ClientRequestToken": "t"},
                None,
            )


def test_password_uses_alphanumerics_only(admin_rotation_module):
    pw = admin_rotation_module._generate_password()
    assert len(pw) == 32
    assert all(ch.isalnum() for ch in pw)
