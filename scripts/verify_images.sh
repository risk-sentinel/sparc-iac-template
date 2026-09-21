#!/usr/bin/env bash
# =============================================================================
# verify_images.sh (#385) — deploy-time image supply-chain gate.
#
# For each ECS image in .security/image-signing-policy.json:
#   1. read its tag from the prod tfvars (the policy's tag_var),
#   2. resolve tag -> immutable @sha256 digest via `aws ecr describe-images`,
#   3. cosign-verify the digest against the per-image identity_regexp + issuer
#      (and the CycloneDX SBOM attestation when require_attestation is true),
#   4. emit <KEY>_IMAGE=<registry>/<repo>@<digest> to $GITHUB_OUTPUT (+ stdout).
#
# FAILS CLOSED: any unresolved tag / missing or wrong-identity signature exits
# non-zero, so the caller's `terraform plan/apply` never runs. No masking.
#
# Deps (present in the deploy runner + cosign-installer step): aws, cosign,
# python3 (stdlib json only — no pyyaml/yq dependency). Runbook:
# docs/dev/image_signing_gate.md.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="${IMAGE_POLICY:-$REPO_ROOT/.security/image-signing-policy.json}"
TFVARS="${TFVARS_FILE:-$REPO_ROOT/AWS/ECS/envs/prod/terraform.tfvars}"
REGION="${AWS_REGION:-us-east-1}"

# --resolve-only (or RESOLVE_ONLY=true): resolve tag -> digest and emit the
# *_IMAGE refs WITHOUT cosign verify/verify-attestation. Used by plan-on-push so
# the preview plan matches the live digest-pinned task def (#446) — verification
# stays a deploy-time gate. No cosign dependency in this mode.
RESOLVE_ONLY="${RESOLVE_ONLY:-false}"
[[ "${1:-}" == "--resolve-only" ]] && RESOLVE_ONLY=true

die() { echo "::error::$*" >&2; exit 1; }

[[ -f "$POLICY" ]] || die "signing policy not found: $POLICY"
[[ -f "$TFVARS" ]] || die "tfvars not found: $TFVARS"
deps=(aws python3)
[[ "$RESOLVE_ONLY" == "true" ]] || deps+=(cosign)
for bin in "${deps[@]}"; do
  command -v "$bin" >/dev/null 2>&1 || die "missing dependency: $bin"
done

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

# Let cosign read the private ECR registry (signatures live alongside the image).
# Skipped in --resolve-only (no cosign).
if [[ "$RESOLVE_ONLY" != "true" ]]; then
  aws ecr get-login-password --region "$REGION" \
    | cosign login "$REGISTRY" -u AWS --password-stdin >/dev/null
fi

# Flatten the policy to TSV rows (one python3 call, stdlib json only).
issuer="$(python3 -c "import json; print(json.load(open('$POLICY'))['issuer'])")"
mapfile -t ROWS < <(python3 -c "
import json
for im in json.load(open('$POLICY'))['images']:
    print('\t'.join([im['key'], im['repo'], im['tag_var'],
                     im['identity_regexp'], str(im.get('require_attestation', True)).lower()]))
")
[[ "${#ROWS[@]}" -gt 0 ]] || die "no images in policy"

read_tag() { # tfvars value for a var name:  foo_tag = "v1.2.3" # comment
  local name="$1"
  grep -E "^[[:space:]]*${name}[[:space:]]*=" "$TFVARS" | head -1 \
    | sed -E 's/^[^=]*=[[:space:]]*"([^"]+)".*/\1/'
}

# Verify trying BOTH cosign signature-discovery schemes (#458): the legacy `.sig`
# tag first (how nginx/heimdall are signed), then the OCI 1.1 referrers API (newer
# cosign default — how example is signed). Succeeds if EITHER finds a valid
# signature with the expected identity/issuer — no weakening of the gate, just
# looks in both storage locations. Args: <errfile> <cosign subcommand + args...>
cosign_verify_either() {
  local errfile="$1"; shift
  cosign "$@" >/dev/null 2>"$errfile" && return 0
  cosign "$@" --registry-referrers-mode oci-1-1 >/dev/null 2>"$errfile" && return 0
  return 1
}

fail=0
for row in "${ROWS[@]}"; do
  IFS=$'\t' read -r key repo tag_var identity require_att <<< "$row"
  tag="$(read_tag "$tag_var")"
  if [[ -z "$tag" ]]; then
    echo "::error::no tag for '$tag_var' in $TFVARS" >&2; fail=1; continue
  fi

  digest="$(aws ecr describe-images --repository-name "$repo" --image-ids "imageTag=$tag" \
    --region "$REGION" --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || true)"
  if [[ -z "$digest" || "$digest" == "None" ]]; then
    echo "::error::could not resolve $repo:$tag to a digest" >&2; fail=1; continue
  fi
  ref="${REGISTRY}/${repo}@${digest}"

  echo "::group::$([[ "$RESOLVE_ONLY" == "true" ]] && echo resolve || echo verify) ${key} — ${repo}:${tag}"
  echo "  digest: ${digest}"
  if [[ "$RESOLVE_ONLY" != "true" ]]; then
    if ! cosign_verify_either cosign.err verify "$ref" \
          --certificate-identity-regexp "$identity" \
          --certificate-oidc-issuer "$issuer"; then
      echo "::error::signature verification FAILED for ${repo}:${tag} (expected identity ${identity}; tried tag + OCI-referrers)" >&2
      sed 's/^/    /' cosign.err >&2 || true
      echo "::endgroup::"; fail=1; continue
    fi
    echo "  signature: VERIFIED"

    if [[ "$require_att" == "true" ]]; then
      if ! cosign_verify_either att.err verify-attestation "$ref" --type cyclonedx \
            --certificate-identity-regexp "$identity" \
            --certificate-oidc-issuer "$issuer"; then
        echo "::error::CycloneDX attestation verification FAILED for ${repo}:${tag}" >&2
        sed 's/^/    /' att.err >&2 || true
        echo "::endgroup::"; fail=1; continue
      fi
      echo "  attestation (cyclonedx): VERIFIED"
    else
      echo "  attestation: not required by policy (require_attestation=false)"
    fi
  else
    echo "  resolve-only: skipping cosign verify (preview plan; verification stays a deploy gate)"
  fi

  out_var="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')_IMAGE"
  echo "  -> ${out_var}=${ref}"
  echo "${out_var}=${ref}"
  [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "${out_var}=${ref}" >> "$GITHUB_OUTPUT"
  echo "::endgroup::"
done

rm -f cosign.err att.err
if [[ "$RESOLVE_ONLY" == "true" ]]; then
  [[ "$fail" -eq 0 ]] || die "image digest resolution FAILED — could not pin all tags."
  echo "resolve-only: all images pinned by digest (no signature verification — preview plan)."
else
  [[ "$fail" -eq 0 ]] || die "image signing gate FAILED — deploy blocked (fail-closed)."
  echo "image signing gate: all images verified + pinned by digest."
fi
