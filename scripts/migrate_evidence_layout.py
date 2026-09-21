#!/usr/bin/env python3
"""
One-time migration of S3 security-evidence into the canonical #537 layout.

#537 Phase 2. Reorganizes the legacy source-first evidence keys

    <source>/<repo>/<date|latest>/<rest...>

into the canonical boundary-first layout

    <boundary>/<date|latest>/<repo>/<source>/<rest...>

Examples:
    sonarqube/sparc-iac/2026-07-13/sonarqube-hdf.json
        -> sparc/2026-07-13/sparc-iac/sonarqube/sparc-iac-sonarqube-hdf.json
    sca/container-build-sign/2026-06-10/bom/ci-runner.cdx.json
        -> sparc/2026-06-10/container-build-sign/sca/bom/ci-runner.cdx.json

Design notes:
  * COPY, not move — legacy keys stay live during the transition (producers keep
    writing them until they cut over; #537 Phase 3 cleans them up). Nothing is
    deleted here.
  * SonarQube HDF filenames are normalized to <repo>-sonarqube-hdf.json to match
    the live producer (sparc#741). SCA keeps its full sub-structure (bom/, vuln/).
  * Idempotent — a target that already exists with the same size is skipped, so
    re-runs are cheap and versioning isn't churned. Collisions resolve newest-wins.
  * Encryption is sent EXPLICITLY as aws:kms on every copy (#715). Relying on the
    bucket's default encryption is not enough any more: DenyUnencryptedEvidencePuts
    now covers <boundary>/* and tests the REQUEST key s3:x-amz-server-side-encryption,
    which default encryption does not populate. A copy without the header is denied
    outright, admin or not, because an explicit Deny beats every Allow. No key id is
    pinned — the bucket default CMK applies.
  * Every S3 call passes ExpectedBucketOwner (the account running the migration, or
    --expected-bucket-owner) so a bucket-ownership swap can't redirect the read/write.
  * Dry-run by DEFAULT. Pass --apply to actually copy. Gaps (a source/repo that
    never came online) are expected and just logged.

Requires cross-prefix read+write on the evidence bucket — an operator/admin run,
not an emit role (those are write-own-prefix only).
"""
import argparse
import sys

import boto3

# Legacy source prefixes that carry producer HDF/SCA evidence. `_rollup` is left
# to container-build-sign#151; the <date>/<sha> compliance output and infra logs
# (cloudtrail/, alb-logs/, attestations/, ...) are a different scheme and untouched.
SOURCES = ("sonarqube", "sca")


def _is_date(s):
    return len(s) == 10 and s[4] == "-" and s[7] == "-" and s.replace("-", "").isdigit()


def canonical_key(boundary, source, key):
    """Map a legacy `<source>/<repo>/<dateslot>/<rest>` key to the canonical layout.

    Returns None for keys that don't fit the expected shape (e.g. sca/_rollup/*),
    which are skipped.
    """
    parts = key.split("/")
    # need at least source/repo/dateslot/file
    if len(parts) < 4 or parts[0] != source:
        return None
    repo, dateslot, rest = parts[1], parts[2], "/".join(parts[3:])
    if repo == "_rollup":
        return None  # aggregate output — CBS#151 decides its canonical path
    if dateslot != "latest" and not _is_date(dateslot):
        return None
    if source == "sonarqube":
        # Normalize the single HDF filename to match the live producer convention
        # (sparc#741 writes <repo>-sonarqube-hdf.json under <repo>/sonarqube/); the
        # legacy tree has a mix of sonarqube-hdf.json and <repo>-sonarqube-hdf.json.
        rest = f"{repo}-sonarqube-hdf.json"
    return f"{boundary}/{dateslot}/{repo}/{source}/{rest}"


def _iter_objects(s3, bucket, prefix, owner):
    """Yield every object under `prefix`, flattening pagination."""
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix, ExpectedBucketOwner=owner):
        yield from page.get("Contents", [])


def build_plan(s3, bucket, sources, boundary, owner):
    """Return (plan, malformed) where plan maps target key -> (src_key, size, mtime).

    When several legacy keys collapse to one canonical target (e.g. a `latest` slot
    with both sonarqube-hdf.json and <repo>-sonarqube-hdf.json) the NEWEST source wins.
    """
    plan, malformed = {}, 0
    for source in sources:
        n_src = 0
        for obj in _iter_objects(s3, bucket, f"{source}/", owner):
            n_src += 1
            target = canonical_key(boundary, source, obj["Key"])
            if target is None:
                malformed += 1
                continue
            prev = plan.get(target)
            if prev is None or obj["LastModified"] > prev[2]:
                plan[target] = (obj["Key"], obj["Size"], obj["LastModified"])
        if n_src == 0:
            print(f"NOTE: no objects under '{source}/' — nothing to migrate for this "
                  "source (expected if it never came online)")
    return plan, malformed


def _target_is_current(s3, bucket, target, size, owner):
    """True if `target` already exists with the same size (idempotent skip)."""
    try:
        head = s3.head_object(Bucket=bucket, Key=target, ExpectedBucketOwner=owner)
    except s3.exceptions.ClientError:
        return False
    return head["ContentLength"] == size


def execute_plan(s3, bucket, plan, owner, apply):
    """Copy each planned object (or print it in dry-run). Return (copied, skipped)."""
    copied = skipped = 0
    for target, (src_key, size, _mtime) in sorted(plan.items()):
        if _target_is_current(s3, bucket, target, size, owner):
            skipped += 1
            continue
        print(f"{'COPY' if apply else 'DRY '} {src_key}\n        -> {target}")
        if apply:
            s3.copy_object(
                Bucket=bucket,
                Key=target,
                CopySource={"Bucket": bucket, "Key": src_key},
                ExpectedBucketOwner=owner,
                ExpectedSourceBucketOwner=owner,
                # Required, not decorative (#715). The bucket policy denies any
                # PutObject/CopyObject under <boundary>/* whose request omits
                # this header; the bucket's default encryption does NOT satisfy
                # it, because the condition reads the request, not the result.
                ServerSideEncryption="aws:kms",
            )
        copied += 1
    return copied, skipped


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--bucket", required=True, help="evidence bucket name")
    ap.add_argument("--boundary", default="sparc", help="canonical boundary segment (default: sparc)")
    ap.add_argument("--sources", nargs="+", default=list(SOURCES), help=f"legacy source prefixes (default: {' '.join(SOURCES)})")
    ap.add_argument("--expected-bucket-owner", help="account id that must own the bucket (default: the caller's account)")
    ap.add_argument("--apply", action="store_true", help="actually copy (default: dry-run)")
    args = ap.parse_args()

    s3 = boto3.client("s3")
    owner = args.expected_bucket_owner or boto3.client("sts").get_caller_identity()["Account"]

    plan, malformed = build_plan(s3, args.bucket, args.sources, args.boundary, owner)
    copied, skipped = execute_plan(s3, args.bucket, plan, owner, args.apply)

    verb = "copied" if args.apply else "would copy"
    print(f"\nSummary: {verb} {copied}, skipped (already current) {skipped}, "
          f"unmapped/left-in-place {malformed}.")
    if not args.apply:
        print("Dry-run only. Re-run with --apply to perform the copy.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
