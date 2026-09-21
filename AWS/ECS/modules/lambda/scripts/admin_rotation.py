"""
Admin-credential rotation Lambda for SPARC (sparc-iac#151 + #197).

Implements the AWS Secrets Manager 4-step rotation protocol on top of SPARC's
POST /api/admin/refresh_credentials contract (risk-sentinel/sparc#403 v2):

  createSecret  -> generate new password, put_secret_value with AWSPENDING.
  setSecret     -> Bearer-token POST to SPARC carrying secret_version_id.
                   SPARC reads the AWSPENDING version directly from Secrets
                   Manager and updates the DB row.
  testSecret    -> re-issue the same POST. SPARC's contract guarantees a
                   200 "unchanged" on the second call when the version is
                   already applied; that confirms end-to-end success.
  finishSecret  -> update_secret_version_stage to promote AWSPENDING to
                   AWSCURRENT and demote previous AWSCURRENT to AWSPREVIOUS.

Auth model (#197): the Lambda fetches a sparc_sa_* service-account Bearer
token from Secrets Manager (ROTATION_TOKEN_SECRET_ARN) on each invocation
and sends it as Authorization: Bearer <token>. No SigV4 signing — SPARC
chose the simpler Bearer path on the v2 design refinement to avoid adding
SigV4 verification middleware.

The contract is rollback-by-omission: if any step fails, AWSPENDING is left
in place and AWSCURRENT is unchanged. Consumers continue to read the old
password until a subsequent rotation succeeds. Failures publish to the SNS
topic (best-effort) and the DLQ catches Lambda invocation failures.

Environment variables:
  SPARC_API_BASE_URL          -- fully-qualified base URL (https://...).
  SECRET_ARN                  -- ARN of the admin-credentials secret.
  ROTATION_TOKEN_SECRET_ARN   -- ARN of the Bearer-token secret (#197).
  SNS_TOPIC_ARN               -- ARN of the alarms SNS topic for failure publish.

Lambda event shape (provided by Secrets Manager):
  {
    "Step":    "createSecret" | "setSecret" | "testSecret" | "finishSecret",
    "SecretId":   "<secret arn>",
    "ClientRequestToken": "<uuid>"
  }
"""

from __future__ import annotations

import json
import logging
import os
import secrets
import string
from datetime import datetime, timezone
from typing import Any

import boto3
import urllib.error
import urllib.request

logger = logging.getLogger()
logger.setLevel(logging.INFO)

PASSWORD_LENGTH = 32
# Match the existing static random_password.admin in modules/secrets:
# `special = false` -- alphanumerics only. Avoids shell-escape surprises in
# any downstream consumer that pulls the secret as a literal string.
PASSWORD_ALPHABET = string.ascii_letters + string.digits

REFRESH_PATH = "/api/admin/refresh_credentials"


def handler(event: dict, context: Any) -> dict:
    step = event["Step"]
    secret_id = event["SecretId"]
    token = event["ClientRequestToken"]

    logger.info("Rotation step=%s secret=%s token=%s", step, secret_id, token)

    sm = boto3.client("secretsmanager")
    _ensure_rotation_enabled(sm, secret_id, token)

    dispatch = {
        "createSecret": _create_secret,
        "setSecret": _set_secret,
        "testSecret": _test_secret,
        "finishSecret": _finish_secret,
    }
    fn = dispatch.get(step)
    if fn is None:
        raise ValueError(f"Unknown rotation step: {step}")

    try:
        return fn(sm, secret_id, token) or {}
    except Exception as exc:
        _publish_failure(step, secret_id, token, exc)
        raise


# ---------------------------------------------------------------------------
# Step implementations
# ---------------------------------------------------------------------------


def _create_secret(sm, secret_id: str, token: str) -> None:
    """Generate a new password and store it as AWSPENDING under the rotation token."""
    # Idempotency: if AWSPENDING already exists for this token, do nothing.
    if _has_pending(sm, secret_id, token):
        logger.info("AWSPENDING already exists for token=%s; skipping createSecret", token)
        return

    # Read the AWSCURRENT value so we preserve the non-rotating fields
    # (sparc_admin_email, smtp_username, smtp_password). Only sparc_admin_password
    # rotates here.
    current = sm.get_secret_value(SecretId=secret_id, VersionStage="AWSCURRENT")
    payload = json.loads(current["SecretString"])
    payload["sparc_admin_password"] = _generate_password()

    sm.put_secret_value(
        SecretId=secret_id,
        ClientRequestToken=token,
        SecretString=json.dumps(payload),
        VersionStages=["AWSPENDING"],
    )
    logger.info("Wrote AWSPENDING version under token=%s", token)


def _set_secret(sm, secret_id: str, token: str) -> None:
    """Tell SPARC to apply the AWSPENDING version to its admin user."""
    _post_refresh(secret_version_id=token)
    logger.info("setSecret: SPARC applied AWSPENDING token=%s", token)


def _test_secret(sm, secret_id: str, token: str) -> None:
    """Idempotent re-issue of the same call. Confirms end-to-end success.

    SPARC's contract: a second POST with the same secret_version_id returns
    HTTP 200 "unchanged". Anything else means setSecret didn't fully take
    and we abort the rotation (AWSPENDING stays in place; AWSCURRENT is
    untouched).
    """
    body = _post_refresh(secret_version_id=token)
    status = body.get("status")
    if status not in ("ok", "unchanged"):
        raise RuntimeError(f"testSecret got unexpected status={status!r} body={body!r}")
    logger.info("testSecret: SPARC reports status=%s for token=%s", status, token)


def _finish_secret(sm, secret_id: str, token: str) -> None:
    """Promote AWSPENDING to AWSCURRENT.

    Secrets Manager handles the AWSCURRENT->AWSPREVIOUS demote automatically
    when we move AWSCURRENT to a new VersionId. The 'RemoveFromVersionId'
    parameter tells it which version is losing AWSCURRENT.
    """
    metadata = sm.describe_secret(SecretId=secret_id)
    current_version = None
    for version_id, stages in metadata.get("VersionIdsToStages", {}).items():
        if "AWSCURRENT" in stages and version_id != token:
            current_version = version_id
            break

    sm.update_secret_version_stage(
        SecretId=secret_id,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version,
    )
    logger.info(
        "finishSecret: promoted token=%s to AWSCURRENT (previous=%s)",
        token,
        current_version,
    )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _ensure_rotation_enabled(sm, secret_id: str, token: str) -> None:
    """Validate the secret is configured for rotation and the token is in
    AWSPENDING (or freshly created and unstaged).

    Mirrors the example AWS rotation Lambda's pre-flight check. Prevents
    accidental invocation against an unrelated secret.
    """
    metadata = sm.describe_secret(SecretId=secret_id)
    if not metadata.get("RotationEnabled"):
        raise RuntimeError(f"Secret {secret_id} is not configured for rotation")
    versions = metadata.get("VersionIdsToStages", {})
    if token not in versions:
        # Allowed -- createSecret hasn't run yet.
        return
    stages = versions[token]
    if "AWSCURRENT" in stages:
        # Already promoted -- nothing to do.
        logger.info("Token=%s is already AWSCURRENT; rotation is a no-op", token)
        return
    if "AWSPENDING" not in stages:
        raise RuntimeError(
            f"Token {token} is not in AWSPENDING for secret {secret_id} (stages={stages})"
        )


def _has_pending(sm, secret_id: str, token: str) -> bool:
    metadata = sm.describe_secret(SecretId=secret_id)
    stages = metadata.get("VersionIdsToStages", {}).get(token, [])
    return "AWSPENDING" in stages


def _generate_password(length: int = PASSWORD_LENGTH) -> str:
    return "".join(secrets.choice(PASSWORD_ALPHABET) for _ in range(length))


def _fetch_bearer_token() -> str:
    """Fetch the SPARC service-account Bearer token from Secrets Manager.

    Pulled per-invocation so token rotation on the SPARC side takes effect
    on the next rotation without redeploying this Lambda. The Lambda's IAM
    role is scoped to GetSecretValue on this single secret only.
    """
    arn = os.environ["ROTATION_TOKEN_SECRET_ARN"]
    sm = boto3.client("secretsmanager")
    resp = sm.get_secret_value(SecretId=arn)
    token = resp.get("SecretString", "").strip()
    if not token:
        raise RuntimeError(
            f"ROTATION_TOKEN_SECRET_ARN={arn} is empty; populate per "
            "docs/dev/admin_rotation.md before enabling rotation."
        )
    return token


def _post_refresh(secret_version_id: str) -> dict:
    """Bearer-token POST to SPARC's refresh endpoint (#197).

    Per the v2 design (risk-sentinel/sparc#403), SPARC validates a
    sparc_sa_* service-account Bearer token rather than SigV4. The token
    lives in Secrets Manager (ROTATION_TOKEN_SECRET_ARN) and is fetched
    on each call. SPARC matches the token against the bound service
    account's allow-list and rejects with HTTP 401/403 otherwise.
    """
    base_url = os.environ["SPARC_API_BASE_URL"].rstrip("/")
    url = f"{base_url}{REFRESH_PATH}"
    body = json.dumps({"secret_version_id": secret_version_id}).encode("utf-8")
    token = _fetch_bearer_token()

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {token}",
    }
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        # Surface SPARC's structured error body so the caller can decide
        # whether to abort the rotation or retry.
        try:
            err_body = json.loads(e.read())
        except Exception:
            err_body = {"error": e.reason}
        raise RuntimeError(
            f"SPARC refresh_credentials returned {e.code}: {err_body}"
        ) from None


def _publish_failure(step: str, secret_id: str, token: str, exc: Exception) -> None:
    """Best-effort SNS publish on rotation failure.

    Lambda DLQ catches invocation-level failures; this hook gives a richer
    payload tied to the rotation context. Swallow publish errors so we don't
    mask the original exception.
    """
    topic = os.environ.get("SNS_TOPIC_ARN")
    if not topic:
        return
    try:
        sns = boto3.client("sns")
        sns.publish(
            TopicArn=topic,
            Subject=f"Admin rotation failed at step={step}",
            Message=json.dumps(
                {
                    "step": step,
                    "secret_id": secret_id,
                    "client_request_token": token,
                    "error": repr(exc),
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                }
            ),
        )
    except Exception as publish_err:
        logger.warning("SNS publish failed: %r (original error: %r)", publish_err, exc)
