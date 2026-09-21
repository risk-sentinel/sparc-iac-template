# Hibernate/Wake desired-state watchdog (#573).
#
# Runs on EventBridge Scheduler (~5 min). Computes the state prod SHOULD be in
# from the clock (DST-aware America/New_York, 06:00-21:00 ET = awake) and, if
# actual != desired, triggers the existing hibernate/wake GitHub workflow via
# workflow_dispatch. This makes recovery independent of GitHub cron latency (the
# 2026-07-24 incident: a wake fired 32 min late) — any tick within the interval
# self-heals a missed/late transition. Bounds recovery to one check interval.
#
# MUST run OUTSIDE the VPC: hibernate destroys the NAT gateway, so a private-
# subnet Lambda would lose egress exactly when it needs to call GitHub to wake
# prod (deadlock). Non-VPC → AWS-managed egress, independent of the NAT.
#
# Auth: reuses the org GitHub App (sparc-iac-diagram-bot). Per invocation it
# reads the App id/key/installation from Secrets Manager, signs a short-lived
# RS256 JWT, exchanges it for a ~1h installation token, and dispatches. No
# long-lived credential to rotate. The RS256 signing is pure-stdlib (hashlib +
# int math) ON PURPOSE — this safety-critical net must package as a single .py
# with NO native-crypto dependency (cryptography/PyJWT) to build or break.
#
# NIST: CP-10 (recovery), SI-4 (monitoring — emits a drift-correction metric).

import base64
import hashlib
import json
import os
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import boto3

GITHUB_API = "https://api.github.com"
# Shared GitHub REST headers (avoid duplicating the literals — sonar S1192).
GH_ACCEPT = "application/vnd.github+json"
GH_API_VERSION = "2022-11-28"
ET = ZoneInfo("America/New_York")

# Awake window (local ET), inclusive-exclusive: [06:00, 21:00) = awake.
WAKE_HOUR = 6
SLEEP_HOUR = 21

# ASN.1 DigestInfo prefix for SHA-256 (RFC 8017 §9.2), prepended to the digest
# to build the PKCS#1 v1.5 signature payload.
_SHA256_DIGESTINFO = bytes.fromhex("3031300d060960864801650304020105000420")


# --- pure-stdlib RS256 (avoids vendoring cryptography/PyJWT) -----------------


def _der_read_tlv(data: bytes, i: int):
    """Read one ASN.1 DER tag-length-value at offset i; return (tag, value, next_i)."""
    tag = data[i]
    length = data[i + 1]
    i += 2
    if length & 0x80:
        n = length & 0x7F
        length = int.from_bytes(data[i : i + n], "big")
        i += n
    return tag, data[i : i + length], i + length


def _rsa_n_d_from_pem(pem: str):
    """Extract (modulus n, private exponent d) from an RSA private key PEM.

    Handles both PKCS#1 (`BEGIN RSA PRIVATE KEY`) and PKCS#8
    (`BEGIN PRIVATE KEY`, PrivateKeyInfo wrapping the PKCS#1 DER).
    """
    der = base64.b64decode("".join(l for l in pem.strip().splitlines() if "-----" not in l))
    _, seq, _ = _der_read_tlv(der, 0)  # outer SEQUENCE body
    # First element: INTEGER version (both formats).
    _, _v, i = _der_read_tlv(seq, 0)
    tag1, val1, i = _der_read_tlv(seq, i)
    if tag1 == 0x30:  # PKCS#8: SEQUENCE (AlgorithmIdentifier) → next OCTET STRING is PKCS#1
        _, pkcs1, _ = _der_read_tlv(seq, i)  # OCTET STRING body = PKCS#1 DER
        _, inner, _ = _der_read_tlv(pkcs1, 0)  # inner RSAPrivateKey SEQUENCE body
        _, _v2, j = _der_read_tlv(inner, 0)  # version
        _, n_b, j = _der_read_tlv(inner, j)  # modulus
        _, _e, j = _der_read_tlv(inner, j)  # publicExponent
        _, d_b, j = _der_read_tlv(inner, j)  # privateExponent
        return int.from_bytes(n_b, "big"), int.from_bytes(d_b, "big")
    # PKCS#1: val1 = modulus n, then publicExponent, then privateExponent d.
    n = int.from_bytes(val1, "big")
    _, _e, i = _der_read_tlv(seq, i)
    _, d_b, i = _der_read_tlv(seq, i)
    return n, int.from_bytes(d_b, "big")


def _rs256_sign(signing_input: bytes, n: int, d: int) -> bytes:
    """RSASSA-PKCS1-v1_5 sign with SHA-256, pure stdlib."""
    k = (n.bit_length() + 7) // 8
    t = _SHA256_DIGESTINFO + hashlib.sha256(signing_input).digest()
    em = b"\x00\x01" + b"\xff" * (k - len(t) - 3) + b"\x00" + t
    sig = pow(int.from_bytes(em, "big"), d, n)
    return sig.to_bytes(k, "big")


def _b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def _make_app_jwt(app_id, private_key_pem: str) -> str:
    now = int(time.time())
    header = _b64url(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = _b64url(
        json.dumps({"iat": now - 60, "exp": now + 540, "iss": str(app_id)}, separators=(",", ":")).encode()
    )
    signing_input = f"{header}.{payload}".encode()
    n, d = _rsa_n_d_from_pem(private_key_pem)
    return f"{signing_input.decode()}.{_b64url(_rs256_sign(signing_input, n, d))}"


# --- state + GitHub -----------------------------------------------------------


def _desired_state(now_et: datetime) -> str:
    """'awake' during 06:00-21:00 ET, else 'asleep'. DST handled by zoneinfo."""
    return "awake" if WAKE_HOUR <= now_et.hour < SLEEP_HOUR else "asleep"


def _actual_state() -> str:
    """Read live prod state. ECS desiredCount is the authoritative signal:
    hibernate sets it to 0, wake restores it. >0 = awake."""
    ecs = boto3.client("ecs")
    svc = ecs.describe_services(
        cluster=os.environ["ECS_CLUSTER"], services=[os.environ["ECS_SERVICE"]]
    )["services"][0]
    return "awake" if svc["desiredCount"] > 0 else "asleep"


def _app_installation_token() -> str:
    """Mint a short-lived GitHub App installation token from the App private key
    stored in Secrets Manager (JSON: {app_id, installation_id, private_key})."""
    sm = boto3.client("secretsmanager")
    creds = json.loads(
        sm.get_secret_value(SecretId=os.environ["GH_APP_SECRET_ARN"])["SecretString"]
    )
    assertion = _make_app_jwt(creds["app_id"], creds["private_key"])
    req = urllib.request.Request(
        f"{GITHUB_API}/app/installations/{creds['installation_id']}/access_tokens",
        method="POST",
        headers={
            "Authorization": f"Bearer {assertion}",
            "Accept": GH_ACCEPT,
            "X-GitHub-Api-Version": GH_API_VERSION,
        },
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())["token"]


def _run_in_progress(token: str, repo: str, workflow: str) -> bool:
    """Flapping guard: don't dispatch if a hibernate/wake run is already active."""
    req = urllib.request.Request(
        f"{GITHUB_API}/repos/{repo}/actions/workflows/{workflow}/runs"
        "?status=in_progress&per_page=1",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": GH_ACCEPT,
            "X-GitHub-Api-Version": GH_API_VERSION,
        },
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read()).get("total_count", 0) > 0


def _dispatch(token: str, repo: str, workflow: str, action: str) -> None:
    """Fire workflow_dispatch: action=wake|hibernate, environment=prod."""
    body = json.dumps(
        {"ref": "main", "inputs": {"action": action, "environment": "prod"}}
    ).encode()
    req = urllib.request.Request(
        f"{GITHUB_API}/repos/{repo}/actions/workflows/{workflow}/dispatches",
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": GH_ACCEPT,
            "X-GitHub-Api-Version": GH_API_VERSION,
            "Content-Type": "application/json",
        },
    )
    urllib.request.urlopen(req, timeout=15).read()


def _emit_drift_metric(namespace: str, action: str) -> None:
    """Publish the correction WITHOUT dimensions (#710).

    This metric previously carried `Dimensions=[{"Action": action}]` while
    `example-hibernate-watchdog-drift-corrected` alarmed on the bare metric
    name. In CloudWatch those are two different streams, so the alarm watched
    one that nothing ever wrote to, and `treat_missing_data = notBreaching`
    read the emptiness as healthy. It sat in OK through 27 consecutive failed
    wakes on 2026-09-18 while prod was down for eleven hours.

    The action is still in the log line above the call, which is where it is
    actually useful; a dimension here only split the stream the alarm needed.
    """
    boto3.client("cloudwatch").put_metric_data(
        Namespace=namespace,
        MetricData=[
            {
                "MetricName": "HibernateDriftCorrected",
                "Value": 1,
                "Unit": "Count",
            }
        ],
    )


def handler(event, context):
    now_et = datetime.now(timezone.utc).astimezone(ET)
    desired = _desired_state(now_et)
    actual = _actual_state()

    if desired == actual:
        print(f"OK: prod is {actual} as desired ({now_et:%Y-%m-%d %H:%M %Z}).")
        return {"desired": desired, "actual": actual, "action": None}

    action = "wake" if desired == "awake" else "hibernate"
    repo = os.environ["GH_REPO"]  # e.g. risk-sentinel/sparc-iac
    workflow = os.environ["GH_WORKFLOW"]  # e.g. schedule-hibernate.yml
    namespace = os.environ["METRIC_NAMESPACE"]

    token = _app_installation_token()
    if _run_in_progress(token, repo, workflow):
        print(f"DRIFT ({actual}->{desired}) but a {workflow} run is already in "
              f"progress — skipping dispatch this tick.")
        return {"desired": desired, "actual": actual, "action": "skipped-in-progress"}

    print(f"::warning::DRIFT — prod is {actual}, should be {desired} at "
          f"{now_et:%H:%M %Z}. Dispatching {action}.")
    _dispatch(token, repo, workflow, action)
    _emit_drift_metric(namespace, action)
    return {"desired": desired, "actual": actual, "action": action}
