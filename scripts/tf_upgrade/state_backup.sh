#!/usr/bin/env bash
#
# state_backup.sh — Terraform remote-state backup / restore / verify.
#
# Safety net for the Terraform 1.9.x -> 1.15.x upgrade (#290). With a single
# environment there is no non-prod sandbox, so a pre-upgrade backup of the
# remote state is the primary backout mechanism. State objects are SSE-KMS
# encrypted and contain secrets, so this tool keeps everything server-side in
# S3 — nothing is decrypted to the workstation.
#
# Layered safety:
#   1. S3 bucket versioning (already enabled, 90d noncurrent retention)
#   2. an explicit server-side copy to a timestamped backups/<ts>/ prefix (here)
#   3. committed .terraform.lock.hcl files (in git)
#
# The script is portable / public-safe: it derives bucket / key / region / KMS
# per module by parsing each module's backend.hcl (gitignored in the public
# template) — there are no hardcoded account or bucket identifiers here.
#
# Usage:
#   scripts/tf_upgrade/state_backup.sh backup  [--dry-run] [--module M]
#   scripts/tf_upgrade/state_backup.sh verify  [--from <ts>]
#   scripts/tf_upgrade/state_backup.sh restore  --from <ts> (--all | --module M)
#                                               [--version-id <id>] [--confirm] [--dry-run]
#
# Subcommands:
#   backup   Server-side copy every live state object to backups/<UTC-ts>/<key>,
#            capture each live object's VersionId into a manifest, and record the
#            outgoing runner image digest + git HEAD. Reads live keys; writes
#            ONLY under backups/ — never mutates a live state object.
#   verify   Confirm S3 versioning is Enabled, that each live key resolves, and
#            list available backup prefixes (or the contents of --from <ts>).
#   restore  Copy a backed-up object back to its live key (rollback layer 3).
#            DRY-RUN BY DEFAULT — applies only with --confirm.
#
# Requires: awscli v2, git. (No jq dependency — uses --query/--output text.)

set -euo pipefail

# --- module -> directory map (directory holds the backend.hcl) ----------------
MODULES=("bootstrap" "ecs" "ec2" "config")
module_dir() {
  local m="$1"
  case "$m" in
    bootstrap) echo "bootstrap" ;;
    ecs)       echo "AWS/ECS" ;;
    ec2)       echo "AWS/EC2" ;;
    config)    echo "AWS/config" ;;
    *) echo "" ;;
  esac
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --- helpers ------------------------------------------------------------------
err()  { echo "ERROR: $*" >&2; exit 1; }
note() { echo ">> $*" >&2; }

# Extract a quoted scalar (bucket/key/region/kms_key_id) from a backend.hcl.
hcl_get() {
  local file="$1" field="$2"
  grep -E "^[[:space:]]*${field}[[:space:]]*=" "$file" 2>/dev/null \
    | head -1 | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/'
}

# Run a command, or just print it under --dry-run.
DRY_RUN="false"
run() {
  if [[ "$DRY_RUN" = "true" ]]; then
    printf '  [dry-run] %s\n' "$*" >&2
  else
    "$@"
  fi
}

# Resolve backend config for a module into BKT/KEY/REGION/KMS globals.
load_backend() {
  local mod="$1" dir
  dir="$(module_dir "$mod")"
  [[ -n "$dir" ]] || err "unknown module: $mod"
  local hcl="$REPO_ROOT/$dir/backend.hcl"
  [[ -f "$hcl" ]] || err "missing backend config: $dir/backend.hcl"
  BKT="$(hcl_get "$hcl" bucket)"
  KEY="$(hcl_get "$hcl" key)"
  REGION="$(hcl_get "$hcl" region)"
  KMS="$(hcl_get "$hcl" kms_key_id)"
  [[ -n "$BKT" ]] && [[ -n "$KEY" ]] || err "could not parse bucket/key from $dir/backend.hcl"
}

# Selected modules (default: all); set by --module / --all.
SELECTED=()

aws_region_args() { [[ -n "${REGION:-}" ]] && printf -- '--region %s' "$REGION"; }

# --- backup -------------------------------------------------------------------
cmd_backup() {
  local ts manifest tmp_manifest
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  note "Backup timestamp: $ts"

  local entries=()
  local mod
  for mod in "${SELECTED[@]}"; do
    load_backend "$mod"
    # Presence check — patterns that were never applied (e.g. EC2 in an
    # ECS-only deployment) have no state object; record absent and skip.
    # shellcheck disable=SC2046
    if ! aws s3api head-object --bucket "$BKT" --key "$KEY" $(aws_region_args) >/dev/null 2>&1; then
      note "[$mod] no live state object at s3://$BKT/$KEY — skipping (recorded absent)"
      entries+=("$(printf '{"module": "%s", "bucket": "%s", "key": "%s", "present": false}' "$mod" "$BKT" "$KEY")")
      continue
    fi
    note "[$mod] s3://$BKT/$KEY"
    # Capture the live object's current VersionId/ETag/size (read-only).
    local vid etag size lastmod
    # shellcheck disable=SC2046
    vid="$(aws s3api head-object --bucket "$BKT" --key "$KEY" $(aws_region_args) --query 'VersionId' --output text 2>/dev/null || echo None)"
    # shellcheck disable=SC2046
    etag="$(aws s3api head-object --bucket "$BKT" --key "$KEY" $(aws_region_args) --query 'ETag' --output text 2>/dev/null | tr -d '"' || echo "")"
    # shellcheck disable=SC2046
    size="$(aws s3api head-object --bucket "$BKT" --key "$KEY" $(aws_region_args) --query 'ContentLength' --output text 2>/dev/null || echo 0)"
    # shellcheck disable=SC2046
    lastmod="$(aws s3api head-object --bucket "$BKT" --key "$KEY" $(aws_region_args) --query 'LastModified' --output text 2>/dev/null || echo "")"

    local dest="backups/${ts}/${KEY}"
    # Server-side copy to the backup prefix, preserving SSE-KMS.
    # shellcheck disable=SC2046
    run aws s3api copy-object \
      --bucket "$BKT" \
      --key "$dest" \
      --copy-source "${BKT}/${KEY}" \
      --server-side-encryption aws:kms \
      ${KMS:+--ssekms-key-id "$KMS"} \
      $(aws_region_args) \
      --metadata-directive COPY >/dev/null

    entries+=("$(printf '{"module": "%s", "bucket": "%s", "key": "%s", "present": true, "version_id": "%s", "etag": "%s", "size": %s, "last_modified": "%s", "backup_key": "%s"}' \
      "$mod" "$BKT" "$KEY" "$vid" "$etag" "${size:-0}" "$lastmod" "$dest")")
  done

  tmp_manifest="$(mktemp)"
  {
    printf '{\n'
    printf '  "timestamp": "%s",\n' "$ts"
    printf '  "git_head": "%s",\n' "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
    printf '  "runner_digest": "%s",\n' \
      "$(grep -hoE 'sparc-ci-runner@sha256:[a-f0-9]+' "$REPO_ROOT"/.github/workflows/*.yml 2>/dev/null | sort -u | head -1)"
    printf '  "objects": [\n'
    local i
    for i in "${!entries[@]}"; do
      [[ "$i" -gt 0 ]] && printf ',\n'
      printf '    %s' "${entries[$i]}"
    done
    printf '\n  ]\n}\n'
  } >"$tmp_manifest"

  manifest="backups/${ts}/manifest.json"
  if [[ "$DRY_RUN" = "true" ]]; then
    note "Manifest (dry-run, not uploaded):"
    cat "$tmp_manifest" >&2
  else
    load_backend "${SELECTED[0]}"  # any module gives us the shared bucket/region
    # shellcheck disable=SC2046
    # Same SSE-KMS the state copies above use (line ~132): the manifest is the
    # index that makes those backups restorable, so it should not be the one
    # object in the backup prefix written in the clear-by-default path.
    aws s3 cp "$tmp_manifest" "s3://${BKT}/${manifest}" $(aws_region_args) \
      --server-side-encryption aws:kms ${KMS:+--ssekms-key-id "$KMS"} >/dev/null
    note "Manifest uploaded: s3://${BKT}/${manifest}"
  fi
  rm -f "$tmp_manifest"
  echo "$ts"  # stdout: the backup timestamp (for scripting / paste into the issue)
}

# --- verify -------------------------------------------------------------------
cmd_verify() {
  local from="${FROM:-}"
  load_backend "bootstrap"  # shared bucket/region
  note "Bucket: $BKT"
  local status
  # shellcheck disable=SC2046
  status="$(aws s3api get-bucket-versioning --bucket "$BKT" $(aws_region_args) --query 'Status' --output text 2>/dev/null || echo Unknown)"
  note "S3 versioning: $status"
  [[ "$status" = "Enabled" ]] || note "WARNING: bucket versioning is not Enabled — rollback layer 1 unavailable"

  note "Live state objects:"
  local mod
  local vid
  for mod in "${SELECTED[@]}"; do
    load_backend "$mod"
    # shellcheck disable=SC2046
    vid="$(aws s3api head-object --bucket "$BKT" --key "$KEY" $(aws_region_args) --query 'VersionId' --output text 2>/dev/null || echo MISSING)"
    printf '  %-9s s3://%s/%s  (VersionId=%s)\n' "$mod" "$BKT" "$KEY" "$vid" >&2
  done

  if [[ -n "$from" ]]; then
    note "Contents of backups/${from}/:"
    # shellcheck disable=SC2046
    aws s3 ls "s3://${BKT}/backups/${from}/" --recursive $(aws_region_args) >&2 || true
  else
    note "Available backup prefixes:"
    # shellcheck disable=SC2046
    aws s3 ls "s3://${BKT}/backups/" $(aws_region_args) >&2 || note "  (none yet)"
  fi
}

# --- restore (rollback layer 3) ----------------------------------------------
cmd_restore() {
  local from="${FROM:-}" vid="${VERSION_ID:-}"
  [[ -n "$from" ]] || [[ -n "$vid" ]] || err "restore requires --from <ts> (or --version-id with --module)"
  if [[ "$CONFIRM" != "true" ]]; then
    note "DRY-RUN restore (no changes). Re-run with --confirm to apply."
    DRY_RUN="true"
  fi
  local mod
  for mod in "${SELECTED[@]}"; do
    load_backend "$mod"
    local source
    if [[ -n "$vid" ]]; then
      # Restore a specific S3 VersionId of the live object (rollback layer 1).
      source="${BKT}/${KEY}?versionId=${vid}"
    else
      # Restore the explicit backup-prefix copy (rollback layer 2/3).
      # Skip modules with no backup object (e.g. EC2 in an ECS-only deploy).
      # shellcheck disable=SC2046
      if ! aws s3api head-object --bucket "$BKT" --key "backups/${from}/${KEY}" $(aws_region_args) >/dev/null 2>&1; then
        note "[$mod] no backup object at backups/${from}/${KEY} — skipping"
        continue
      fi
      source="${BKT}/backups/${from}/${KEY}"
    fi
    note "[$mod] restore  $source  ->  s3://$BKT/$KEY"
    # shellcheck disable=SC2046
    run aws s3api copy-object \
      --bucket "$BKT" \
      --key "$KEY" \
      --copy-source "$source" \
      --server-side-encryption aws:kms \
      ${KMS:+--ssekms-key-id "$KMS"} \
      $(aws_region_args) \
      --metadata-directive COPY >/dev/null
  done
  [[ "$CONFIRM" = "true" ]] && note "Restore complete. Run a 'terraform plan' to confirm state integrity."
}

usage() {
  sed -n '3,46p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# --- arg parsing --------------------------------------------------------------
main() {
  [[ $# -ge 1 ]] || usage 1
  local cmd="$1"; shift
  CONFIRM="false"; FROM=""; VERSION_ID=""
  local want_all="false" want_mod=""
  while [[ $# -gt 0 ]]; do
    local arg="$1"
    case "$arg" in
      --dry-run)    DRY_RUN="true" ;;
      --confirm)    CONFIRM="true" ;;
      --all)        want_all="true" ;;
      --module)     want_mod="${2:-}"; shift ;;
      --from)       FROM="${2:-}"; shift ;;
      --version-id) VERSION_ID="${2:-}"; shift ;;
      -h|--help)    usage 0 ;;
      *) err "unknown flag: $arg" ;;
    esac
    shift
  done

  if [[ -n "$want_mod" ]]; then
    [[ -n "$(module_dir "$want_mod")" ]] || err "unknown module: $want_mod (valid: ${MODULES[*]})"
    SELECTED=("$want_mod")
  else
    SELECTED=("${MODULES[@]}")
  fi

  command -v aws >/dev/null 2>&1 || err "awscli not found on PATH"

  case "$cmd" in
    backup)  cmd_backup ;;
    verify)  cmd_verify ;;
    restore)
      # restore must be explicit about scope
      [[ "$want_all" = "true" ]] || [[ -n "$want_mod" ]] || err "restore requires --all or --module <M>"
      cmd_restore ;;
    -h|--help|help) usage 0 ;;
    *) err "unknown subcommand: $cmd (backup|verify|restore)" ;;
  esac
}

main "$@"
