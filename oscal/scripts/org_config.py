"""
Shared configuration loader for OSCAL assembly scripts.

Loads organization_variables.yml and provides:
- Deterministic UUID generation via uuid5() for sub-document identifiers
- Fresh UUID v4 for document-level identifiers (per NIST OSCAL document-UUID rule)
- Content-addressable write helper: compares prior doc vs. newly-built doc and
  only rewrites + mints a new document UUID when substantive content changed.
  Prior UUIDs are retained in `metadata.revisions[].props[name=previous-uuid]`.
- Organization/party/system metadata
"""

import hashlib
import json
import os
import uuid
from datetime import datetime, timezone

import yaml

DEFAULT_CONFIG_PATH = "organization_variables.yml"

# Fallback namespace if config file is missing or has no namespace
FALLBACK_NAMESPACE = uuid.UUID("a1b2c3d4-0000-4000-a000-000000000000")

# Namespace used for custom props SPARC adds to OSCAL docs (e.g. previous-uuid)
SPARC_PROPS_NS = "https://risk-sentinel.io/ns/oscal"

# Keys excluded from the content hash at any depth. These fields are either
# timestamps that change every run without representing substantive change, or
# are self-referential (the revisions array tracks prior UUIDs — including it
# in the hash would cause every revision to differ from the next).
_HASH_EXCLUDE_KEYS_ANY_DEPTH = frozenset({
    "last-modified",
    "published",
    "collected",
    "start",
    "end",
    "revisions",
})

# Keys excluded from the content hash only at the document root. The root
# `uuid` is the value we are deciding whether to regenerate.
_HASH_EXCLUDE_KEYS_ROOT_ONLY = frozenset({"uuid"})


def load_config(config_path=None):
    """Load organization_variables.yml, return dict."""
    path = config_path or DEFAULT_CONFIG_PATH
    if os.path.exists(path):
        with open(path) as f:
            return yaml.safe_load(f) or {}
    return {}


def get_namespace(config):
    """Get the project namespace UUID for deterministic generation."""
    ns = config.get("namespace_uuid", "")
    if ns:
        return uuid.UUID(ns)
    return FALLBACK_NAMESPACE


def stable_uuid(config, *parts):
    """Generate a deterministic UUID from namespace + string parts.

    Use for SUB-DOCUMENT identifiers (parties, components, info-types,
    statements, impl-requirements, observations, risks, etc.) so they stay
    stable across regenerations and remain referencable from other documents.

    DO NOT use for document-root `uuid` fields — per NIST OSCAL tutorial
    (https://pages.nist.gov/OSCAL/learn/tutorials/general/metadata/#document-uuid)
    document UUIDs MUST be regenerated when content changes. Use `doc_uuid()`
    together with `maybe_write_oscal()` for that.

    Usage:
        stable_uuid(config, "sc-7", component_uuid)  -> control impl UUID
        stable_uuid(config, "party", role_id)        -> party UUID
    """
    ns = get_namespace(config)
    seed = ":".join(str(p) for p in parts)
    return str(uuid.uuid5(ns, seed))


def doc_uuid():
    """Return a fresh UUID v4 for a document-root `uuid` field.

    Per NIST OSCAL guidance, document UUIDs MUST be regenerated when the
    document's content changes. Callers should use `maybe_write_oscal()`
    which applies this only when content has actually changed.
    """
    return str(uuid.uuid4())


def now_iso():
    """Current UTC timestamp formatted per OSCAL datetime-with-timezone."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _canonicalize_for_hash(obj, is_root):
    """Return `obj` with hash-excluded keys removed, recursively."""
    if isinstance(obj, dict):
        excluded = _HASH_EXCLUDE_KEYS_ANY_DEPTH
        if is_root:
            excluded = excluded | _HASH_EXCLUDE_KEYS_ROOT_ONLY
        return {
            k: _canonicalize_for_hash(v, False)
            for k, v in obj.items()
            if k not in excluded
        }
    if isinstance(obj, list):
        return [_canonicalize_for_hash(x, False) for x in obj]
    return obj


def stable_doc_hash(doc_body):
    """Deterministic SHA-256 of an OSCAL document body, ignoring fields that
    don't represent substantive content change (document uuid, last-modified,
    revisions history, and any nested timestamp fields like collected/start/end).

    `doc_body` is the value under the top-level wrapper key, e.g. for an SSP
    it's the dict at `doc["system-security-plan"]`.
    """
    pruned = _canonicalize_for_hash(doc_body, is_root=True)
    blob = json.dumps(pruned, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


def _build_revision_entry(prior_body):
    """Turn a prior document body into a revisions[] entry that records its
    UUID and timestamp. Called when content changed and we are assigning a
    fresh document UUID.
    """
    md = prior_body.get("metadata", {}) or {}
    entry = {
        "title": md.get("title", "") + " (superseded)" if md.get("title") else "Previous revision",
        "version": md.get("version", "1.0.0"),
        "oscal-version": md.get("oscal-version", "1.1.2"),
        "props": [
            {
                "name": "previous-uuid",
                "ns": SPARC_PROPS_NS,
                "value": prior_body.get("uuid", ""),
            }
        ],
    }
    if md.get("last-modified"):
        entry["last-modified"] = md["last-modified"]
    return entry


def maybe_write_oscal(output_path, new_doc, root_key, marker_dir=None):
    """Content-addressable write for an OSCAL document.

    - Hash `new_doc[root_key]` ignoring uuid / last-modified / revisions.
    - If an existing file at `output_path` has the same hash, leave it alone
      (preserving its uuid and last-modified timestamp). Return False.
    - Otherwise, mint a fresh UUID v4 for `new_doc[root_key]["uuid"]`, set
      `metadata.last-modified` to now, append the prior UUID into
      `metadata.revisions[]` (most-recent-first), write the file. Return True.

    When `marker_dir` is provided, a zero-byte marker file is created on write
    under that directory keyed by the output basename — consumers like
    `package_fedramp.py` use these markers to skip regeneration when nothing
    changed this run.
    """
    body = new_doc[root_key]
    body.setdefault("metadata", {})

    new_hash = stable_doc_hash(body)

    prior_body = None
    prior_hash = None
    if os.path.exists(output_path):
        try:
            with open(output_path) as f:
                prior_doc = json.load(f)
            prior_body = prior_doc.get(root_key)
            if prior_body is not None:
                prior_hash = stable_doc_hash(prior_body)
        except (json.JSONDecodeError, OSError):
            prior_body = None
            prior_hash = None

    if prior_body is not None and prior_hash == new_hash:
        # No substantive change. Keep the prior file untouched so its UUID
        # and last-modified continue to accurately represent the last real
        # revision per NIST document-UUID guidance.
        return False

    # Content changed (or file did not exist). Mint fresh UUID v4 and record
    # the prior revision if there was one.
    body["uuid"] = doc_uuid()
    body["metadata"]["last-modified"] = now_iso()

    revisions = list(body["metadata"].get("revisions") or [])
    # Also carry forward any revisions already recorded on the prior doc so
    # the full history is preserved even if build_*() didn't populate it.
    if prior_body is not None:
        prior_revisions = list((prior_body.get("metadata") or {}).get("revisions") or [])
        # prepend prior doc's own entry first, then older history after
        revisions = [_build_revision_entry(prior_body)] + prior_revisions + revisions
    if revisions:
        body["metadata"]["revisions"] = revisions

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(new_doc, f, indent=2)

    if marker_dir:
        os.makedirs(marker_dir, exist_ok=True)
        marker = os.path.join(marker_dir, os.path.basename(output_path) + ".changed")
        with open(marker, "w") as f:
            f.write(new_hash)

    return True


def get_org_party(config):
    """Return the organization as an OSCAL party dict."""
    org = config.get("organization", {})
    org_uuid = org.get("uuid") or stable_uuid(config, "organization")
    return {
        "uuid": org_uuid,
        "type": "organization",
        "name": org.get("name") or "Organization Name",
    }


def get_parties(config):
    """Return all parties as OSCAL party dicts."""
    parties = [get_org_party(config)]
    for p in config.get("parties", []):
        p_uuid = p.get("uuid") or stable_uuid(config, "party", p.get("role_id", ""))
        parties.append({
            "uuid": p_uuid,
            "type": "person",
            "name": p.get("name") or p.get("title", ""),
        })
    return parties


def get_roles(config):
    """Return all roles from parties config."""
    roles = []
    seen = set()
    for p in config.get("parties", []):
        role_id = p.get("role_id", "")
        if role_id and role_id not in seen:
            roles.append({"id": role_id, "title": p.get("title", role_id)})
            seen.add(role_id)
    # Ensure base roles exist
    for rid, title in [
        ("system-owner", "System Owner"),
        ("authorizing-official", "Authorizing Official"),
        ("system-admin", "System Administrator"),
    ]:
        if rid not in seen:
            roles.append({"id": rid, "title": title})
    return roles


def get_system_info(config):
    """Return system metadata from config."""
    sys = config.get("system", {})
    return {
        "uuid": sys.get("uuid") or stable_uuid(config, "system"),
        "name": sys.get("name") or "SPARC",
        "description": sys.get("description") or "",
        "security_sensitivity_level": sys.get("security_sensitivity_level") or "high",
        "status": sys.get("status") or "operational",
        "information_types": sys.get("information_types") or [],
    }


def get_tool_party(config, tool_name):
    """Return a tool-vendor party dict for assessment results.

    OSCAL 1.1.2 `metadata.parties.type` only accepts `person` or `organization`.
    The assessment tool itself belongs in `assessment-assets/components` with
    type `software`; here we represent the tool vendor as an organization so
    that `responsible-parties`/`origins` references remain valid.
    """
    return {
        "uuid": stable_uuid(config, "tool", tool_name),
        "type": "organization",
        "name": tool_name,
        "remarks": f"Vendor/producer of the {tool_name} assessment tool",
    }
