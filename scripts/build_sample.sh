#!/usr/bin/env bash
#
# build_sample.sh — rebuild sample/ from a run of pipeline evidence (#649).
#
# sample/ is the one bundle that leaves the boundary, and until now it was
# assembled by hand from a procedure reconstructed out of its own README. That
# is the manual step #649 item 4 is about: a bundle nobody can rebuild the same
# way twice is a bundle nobody can re-verify.
#
# Everything here is deterministic. The sanitizer derives its placeholders from
# the sorted set of distinct values, so the same evidence prefix produces a
# byte-identical tree on every run.
#
# Usage:
#   scripts/build_sample.sh <date>/<short-sha>     # e.g. 2026-08-18/49f730a
#   scripts/build_sample.sh --latest               # newest prefix in the bucket
#
# Requires: aws cli with read on the evidence bucket, python3, PyYAML.
#
set -euo pipefail

BUCKET="${EVIDENCE_BUCKET:-your-security-artifacts-bucket}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="NIST_SP-800-53_rev5_HIGH-baseline-resolved-profile_catalog.json"
PATTERNS=(aas ack azure-vm ec2 ecs)

die() { echo "error: $*" >&2; exit 1; }

# Spelled-out counts keep the generated prose stable, so a rebuild that changes
# nothing substantive produces no diff.
count_word() {
  local n="${1:-}"
  case "$n" in
    1) echo one ;; 2) echo two ;;   3) echo three ;; 4) echo four ;;
    5) echo five ;; 6) echo six ;;  7) echo seven ;; 8) echo eight ;;
    9) echo nine ;; *) echo "$n" ;;
  esac
}

readonly SCRIPT_NAME="${0##*/}"
readonly TARGET="${1:-}"

[[ $# -eq 1 ]] || die "usage: $SCRIPT_NAME <date>/<short-sha> | --latest"

if [[ "$TARGET" == "--latest" ]]; then
  # Date prefixes sort lexically AND chronologically, so walking them newest
  # first is sound. The short SHAs beneath them do NOT: they are hex, so
  # `sort`/`tail` over them is an arbitrary pick dressed up as "newest". An
  # earlier cut did exactly that and silently resolved --latest to the OLDEST
  # of the day's three runs. Order the SHAs by object LastModified instead,
  # which is the only ordering that means anything here.
  PREFIX=""
  while read -r d; do
    d="${d%/}"
    [[ -n "$d" ]] || continue
    key=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$d/" \
      --query "sort_by(Contents[?contains(Key, '/fedramp-packages/')], &LastModified)[-1].Key" \
      --output text 2>/dev/null || true)
    [[ -n "$key" && "$key" != "None" ]] || continue
    sha=$(printf '%s' "$key" | cut -d/ -f2)
    [[ -n "$sha" ]] || continue
    PREFIX="$d/$sha"
    break
  done < <(aws s3 ls "s3://$BUCKET/" | awk '/PRE 2[0-9]{3}-/{print $2}' | sort -r)
  [[ -n "$PREFIX" ]] || die "no evidence prefix with fedramp-packages/ found in $BUCKET"
  echo "resolved --latest to $PREFIX"
else
  PREFIX="$TARGET"
fi

SRC="s3://$BUCKET/$PREFIX/fedramp-packages"
aws s3 ls "$SRC/" >/dev/null 2>&1 || die "no fedramp-packages/ under $PREFIX"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
OUT="$WORK/sample"

echo "==> pulling $PREFIX"
mkdir -p "$OUT/fedramp-package"
aws s3 sync "$SRC/" "$OUT/fedramp-package/" --only-show-errors

# Only the patterns the pipeline still emits. A pattern that disappears
# upstream (as `config` did when #597 retired the standalone AWS Config root)
# must disappear here too rather than linger as a package for infrastructure
# that no longer exists.
FOUND=()
for p in "${PATTERNS[@]}"; do
  [[ -d "$OUT/fedramp-package/$p" ]] && FOUND+=("$p")
done
[[ ${#FOUND[@]} -gt 0 ]] || die "no known patterns present under $PREFIX"
for d in "$OUT"/fedramp-package/*/; do
  name="$(basename "$d")"
  case " ${FOUND[*]} " in *" $name "*) ;; *)
    echo "    dropping unknown pattern: $name"; rm -rf "$d" ;;
  esac
done
echo "    patterns: ${FOUND[*]}"

# The resolved catalog is identical across patterns, so it is stored once.
# Proven, not assumed — a divergence would mean the patterns resolved against
# different baselines, which is a finding, not a dedupe opportunity.
echo "==> deduplicating the resolved catalog"
HASHES=$(for p in "${FOUND[@]}"; do
  f="$OUT/fedramp-package/$p/profile/$CATALOG"
  [[ -f "$f" ]] && shasum -a 256 "$f" | cut -d' ' -f1
done | sort -u | wc -l | tr -d ' ')
[[ "$HASHES" == "1" ]] || die "resolved catalog differs across patterns ($HASHES variants) — patterns are not on one baseline"

mkdir -p "$OUT/fedramp-package/shared/catalog" "$OUT/fedramp-package/shared/profile"
mv "$OUT/fedramp-package/${FOUND[0]}/profile/$CATALOG" "$OUT/fedramp-package/shared/catalog/$CATALOG"
git -C "$REPO_ROOT" show "HEAD:sample/fedramp-package/shared/profile/sparc-high-baseline-profile.json" \
  > "$OUT/fedramp-package/shared/profile/sparc-high-baseline-profile.json"
for p in "${FOUND[@]}"; do
  rm -f "$OUT/fedramp-package/$p/profile/$CATALOG"
  cat > "$OUT/fedramp-package/$p/profile/README.md" <<EOF
# profile/ — $p

The resolved baseline catalog that normally sits here is byte-identical across all $(count_word ${#FOUND[@]})
patterns, so it is stored once at:

    ../../shared/catalog/$CATALOG

The tailoring document that produces it is at:

    ../../shared/profile/sparc-high-baseline-profile.json
EOF
done

echo "==> collecting CDEFs"
C="$OUT/cdefs"
mkdir -p "$C/infra-aws" "$C/infra-azure" "$C/vendor-aws-labs" "$C/app-sparc"
cp "$REPO_ROOT/AWS/CDEF/component-definition-template.json" "$C/infra-aws/"
cp -R "$REPO_ROOT/AWS/CDEF/EC2" "$REPO_ROOT/AWS/CDEF/ECS" "$C/infra-aws/"
cp "$REPO_ROOT"/AWS/CDEF/aws-labs/* "$C/vendor-aws-labs/"
cp -R "$REPO_ROOT/Azure/CDEF/AAS" "$REPO_ROOT/Azure/CDEF/ACK" "$REPO_ROOT/Azure/CDEF/VM" "$C/infra-azure/"
# app-sparc CDEFs are generated by the sparc application pipeline, not this
# repo, and are not in the evidence bucket. Carried forward from the committed
# tree, which is already sanitized.
git -C "$REPO_ROOT" archive HEAD sample/cdefs/app-sparc sample/cdefs/MANIFEST.md \
  | tar -x -C "$WORK" -f - \
  || die "cannot recover sample/cdefs/app-sparc + MANIFEST.md from HEAD"
for f in "$C/MANIFEST.md" "$C/app-sparc/component-definition-audit.json"; do
  [[ -f "$f" ]] || die "carry-forward failed: $f absent after extract"
done
find "$OUT" -name '.DS_Store' -delete

echo "==> sanitizing"
python3 "$REPO_ROOT/scripts/public_export/sanitize.py" --root "$WORK" \
  --map "$REPO_ROOT/scripts/public_export/scrub-map.yml" 2>&1 \
  | grep -vE 'WARN: generate_examples' || true

echo "==> verifying"
if ! python3 "$REPO_ROOT/scripts/public_export/verify.py" --root "$WORK" \
     --map "$REPO_ROOT/scripts/public_export/scrub-map.yml"; then
  die "verification failed — sample/ NOT replaced. Add a pattern_replacements rule and re-run."
fi

# Only now is the tree safe to put in the working copy.
echo "==> installing"
rm -rf "$REPO_ROOT/sample/cdefs" "$REPO_ROOT/sample/fedramp-package"
cp -R "$OUT/cdefs" "$OUT/fedramp-package" "$REPO_ROOT/sample/"

cat <<EOF

Rebuilt sample/ from $PREFIX
  patterns: ${FOUND[*]}
  files:    $(find "$REPO_ROOT/sample" -type f | wc -l | tr -d ' ')
  size:     $(du -sh "$REPO_ROOT/sample" | cut -f1)

Still to do by hand:
  - update the snapshot date and commit in sample/README.md and sample/cdefs/MANIFEST.md
  - re-run: oscal-cli profile validate sample/fedramp-package/shared/profile/sparc-high-baseline-profile.json
EOF
