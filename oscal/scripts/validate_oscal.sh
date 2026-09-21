#!/usr/bin/env bash
# =============================================================================
# OSCAL artifact validation — single source of truth for CI and local dev.
#
# Walks every committed OSCAL document in the repo, dispatches to the correct
# `oscal-cli <type> validate` subcommand, and exits non-zero on any error.
#
# Environment:
#   OSCAL_CLI   Path to the oscal-cli launcher. Defaults to `oscal-cli` on $PATH.
#               CI installs the pinned version to the runner; local dev can set
#               this to the build under nist/oscal-cli/target/.
#
# Exit codes:
#   0  all artifacts validated clean
#   1  one or more artifacts failed validation
#   2  oscal-cli not found / usage error
# =============================================================================

set -o pipefail

OSCAL_CLI="${OSCAL_CLI:-oscal-cli}"

if ! command -v "$OSCAL_CLI" >/dev/null 2>&1 && [[ ! -x "$OSCAL_CLI" ]]; then
  echo "ERROR: oscal-cli not found (set OSCAL_CLI=<path> or install on PATH)" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 2

errors=0
total=0

# Usage: validate_one <subcommand> <path>
validate_one() {
  local sub="$1"
  local path="$2"
  total=$((total + 1))
  if ! "$OSCAL_CLI" "$sub" validate "$path" >/tmp/oscal-cli.out 2>&1; then
    echo "FAIL  $sub  $path"
    sed 's/^/  /' /tmp/oscal-cli.out
    errors=$((errors + 1))
  else
    echo "ok    $sub  $path"
  fi
  return 0
}

# --- SSPs --------------------------------------------------------------------
for f in oscal/ssp/*.json; do
  [[ -f "$f" ]] || continue
  validate_one ssp "$f"
done

# --- SARs (infrastructure + application + pipeline) --------------------------
for f in oscal/sar/*.json oscal/sar/application/*.json oscal/sar/pipeline/*.json; do
  [[ -f "$f" ]] || continue
  validate_one ar "$f"
done

# --- POA&Ms ------------------------------------------------------------------
for f in oscal/poam/*.json; do
  [[ -f "$f" ]] || continue
  validate_one poam "$f"
done

# --- SAP(s) ------------------------------------------------------------------
for f in oscal/sap/*.json; do
  [[ -f "$f" ]] || continue
  validate_one ap "$f"
done

# --- Component Definitions ---------------------------------------------------
for f in AWS/CDEF/**/*.json AWS/CDEF/*.json Azure/CDEF/**/*.json Azure/CDEF/*.json; do
  [[ -f "$f" ]] || continue
  # Skip the template — it's a scaffold, not a real CDEF
  case "$f" in
    */component-definition-template.json) continue ;;
    *) ;;
  esac
  validate_one component-definition "$f"
done

# --- Resolved profile catalog ------------------------------------------------
for f in docs/FedRAMP_20x/*catalog*.json; do
  [[ -f "$f" ]] || continue
  validate_one catalog "$f"
done

# --- Inheritance CDEFs -------------------------------------------------------
for f in oscal/inheritance/*.json; do
  [[ -f "$f" ]] || continue
  validate_one component-definition "$f"
done

echo ""
echo "OSCAL validation: $((total - errors))/$total passed, $errors failed"

[[ "$errors" -eq 0 ]]
