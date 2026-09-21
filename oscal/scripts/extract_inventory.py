#!/usr/bin/env python3
"""
extract_inventory.py — deployed-resource inventory from Terraform state (#632).

Reads `terraform show -json` and emits a compact inventory of what is actually
deployed, for `assemble_ssp.py` to render as OSCAL
`system-implementation/inventory-items`.

Why state rather than outputs: there are 327 managed resources across 83 types.
Maintaining ~100 hand-written outputs would drift the moment anyone adds a
resource, and drift in an inventory is worse than no inventory — it reads as
authoritative while being wrong. State is authoritative and self-updating.

SECURITY — this is the point of the module, not a footnote
----------------------------------------------------------
Terraform state contains plaintext secrets: `random_password.result`,
`aws_secretsmanager_secret_version.secret_string`, RDS passwords, private keys.
An inventory built by *excluding* known-bad keys would leak the first attribute
nobody thought of.

So extraction is a strict ALLOWLIST (`SAFE_ATTRS`): an attribute is emitted only
if its key is explicitly listed. Everything else is dropped without inspection.
Adding a key is a deliberate act with a test to match — see
tests/test_extract_inventory.py, which asserts that a synthetic state containing
passwords, secret strings and private keys produces output containing none of
them.

The allowlist is identifiers and non-sensitive descriptors only: names, ARNs,
ids, engine/version, and a few shape attributes an assessor needs to tell two
instances apart. No values, no policy documents, no connection strings.
"""

import argparse
import json
import re
import sys

# --- the allowlist -----------------------------------------------------------
# Identifier-shaped only. If an attribute is not here it is dropped, regardless
# of how harmless it looks. Extend deliberately, with a test.
SAFE_ATTRS = {
    "arn",
    "id",
    "name",
    "bucket",
    "engine",
    "engine_version",
    "instance_class",
    "family",
    "revision",
    "repository_url",
    "function_name",
    "runtime",
    "cidr_block",
    "vpc_id",
    "availability_zone",
    "dns_name",
    "zone_id",
    "cluster",
    "desired_count",
    "launch_type",
    "image_tag_mutability",
    "retention_in_days",
    "kms_key_id",
    "key_id",
    "port",
    "protocol",
}

# Attribute names that must never be emitted even if added to SAFE_ATTRS by
# mistake. Belt to the allowlist's braces — a second, independent check.
FORBIDDEN_PATTERN = re.compile(
    r"(password|secret|token|private_key|certificate_body|result|credential|"
    r"connection_string|bootstrap_token|session)",
    re.IGNORECASE,
)


def walk_modules(module, out):
    """Collect managed resources from the root module and every child module."""
    for res in module.get("resources", []):
        if res.get("mode") != "managed":
            continue  # data sources describe intent, not deployed state
        out.append(res)
    for child in module.get("child_modules", []):
        walk_modules(child, out)
    return out


def safe_attributes(values):
    """Project a resource's attributes down to the allowlist.

    Two independent gates: the key must be in SAFE_ATTRS, AND must not match
    FORBIDDEN_PATTERN. Values are stringified and length-capped so a large
    embedded document cannot ride through on an allowlisted key.
    """
    safe = {}
    for key, val in (values or {}).items():
        if key not in SAFE_ATTRS:
            continue
        if FORBIDDEN_PATTERN.search(key):
            continue
        if val is None or isinstance(val, (dict, list)):
            continue
        text = str(val).strip()
        # Empty values carry no information and violate OSCAL's ^\S(.*\S)?$
        # constraint on prop values, which surfaces as a schema failure far from
        # here (an unset kms_key_id did exactly that).
        if not text or len(text) > 256:
            continue
        safe[key] = text
    return safe


def extract(state):
    """Flatten Terraform state into inventory records."""
    root = state.get("values", {}).get("root_module", {})
    records = []
    for res in walk_modules(root, []):
        values = res.get("values", {})
        attrs = safe_attributes(values)
        # A record with no identifier is not useful in an inventory.
        identifier = attrs.get("arn") or attrs.get("id") or attrs.get("name")
        if not identifier:
            continue
        records.append(
            {
                "type": res["type"],
                "tf_address": res.get("address", ""),
                "tf_name": res.get("name", ""),
                "identifier": identifier,
                "attributes": attrs,
            }
        )
    records.sort(key=lambda r: (r["type"], r["identifier"]))
    return records


def main():
    parser = argparse.ArgumentParser(
        description="Extract a filtered deployed-resource inventory from Terraform state (#632)"
    )
    parser.add_argument(
        "--state-json",
        required=True,
        help="Path to `terraform show -json` output (use - for stdin)",
    )
    parser.add_argument("--output", required=True, help="Path to write the inventory JSON")
    parser.add_argument(
        "--deployed-sha",
        default="",
        help="Git SHA applied to produce this state; recorded alongside the inventory",
    )
    args = parser.parse_args()

    raw = sys.stdin.read() if args.state_json == "-" else open(args.state_json).read()
    try:
        state = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"::error::Could not parse Terraform state JSON: {exc}", file=sys.stderr)
        return 1

    records = extract(state)
    if not records:
        # Fail loud. An empty inventory that is written anyway reads downstream as
        # "nothing is deployed" rather than "extraction broke" — the same failure
        # shape as a glob that matches nothing and reports success (#656).
        print(
            "::error::Inventory extraction produced zero records — state was empty or "
            "unparseable. Refusing to write an empty inventory.",
            file=sys.stderr,
        )
        return 1

    payload = {
        "deployed_sha": args.deployed_sha,
        "resource_count": len(records),
        "resources": records,
    }
    with open(args.output, "w") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")

    print(f"Inventory: {len(records)} resources across "
          f"{len({r['type'] for r in records})} types -> {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
