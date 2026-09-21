#!/usr/bin/env bash
# =============================================================================
# migrate_aws_config_state.sh — move AWS Config from sparc/config into sparc/ecs (#597)
#
# WHY THIS IS A SCRIPT AND NOT A TERRAFORM CHANGE
#
# The configuration recorder, recorder status, delivery channel and conformance
# pack are ACCOUNT-LEVEL SINGLETONS. They cannot be destroyed and recreated —
# there is one per account per region, and dropping the recorder loses the
# configuration history that AWS Config exists to keep. So the resources must be
# IMPORTED into the ECS state, never re-applied into existence.
#
# ORDER MATTERS, AND GETTING IT WRONG DESTROYS LIVE INFRASTRUCTURE
#
# Terraform reads "in state, not in code" as DELETE. So removing the AWS/config
# code while its resources are still in sparc/config means the next apply on that
# root destroys them. `state rm` must therefore happen BEFORE the code is removed,
# never after. This script does import-then-verify-then-rm in that order and
# refuses to continue if the verify step fails.
#
# NOTHING IS DESTROYED AT ANY POINT. The failure mode is a state file naming the
# wrong owner, which is recoverable by re-importing in the other direction.
#
# USAGE
#   ./scripts/migrate_aws_config_state.sh plan     # show what would move, change nothing
#   ./scripts/migrate_aws_config_state.sh import   # step 1: import into sparc/ecs
#   ./scripts/migrate_aws_config_state.sh verify   # step 2: assert ECS plan is clean
#   ./scripts/migrate_aws_config_state.sh release  # step 3: state rm from sparc/config
#
# Run them in that order. `release` refuses unless `verify` has passed.
# =============================================================================
set -euo pipefail

ECS_DIR="AWS/ECS"
CFG_DIR="AWS/config"
MARKER="/tmp/.aws-config-migration-verified"
PLAN_LOG="/tmp/.aws-config-migration-verify.plan"
PLAN_JSON="/tmp/.aws-config-migration-verify.json"
PLAN_BIN="/tmp/.aws-config-migration-verify.tfplan"

# address in sparc/config  ->  address in sparc/ecs
declare -a MOVES=(
  "aws_config_configuration_recorder.main[0]|module.aws_config.aws_config_configuration_recorder.main[0]"
  "aws_config_configuration_recorder_status.main[0]|module.aws_config.aws_config_configuration_recorder_status.main[0]"
  "aws_config_delivery_channel.main[0]|module.aws_config.aws_config_delivery_channel.main[0]"
  "aws_config_conformance_pack.nist[0]|module.aws_config.aws_config_conformance_pack.nist[0]"
  "aws_iam_role.config[0]|module.iam.aws_iam_role.aws_config[0]"
  "aws_iam_role_policy.config_s3[0]|module.iam.aws_iam_role_policy.aws_config_s3[0]"
  "aws_iam_role_policy_attachment.config_managed[0]|module.iam.aws_iam_role_policy_attachment.aws_config_managed[0]"
)

# The source root was deleted once the migration completed (#597). Commands that
# read it must say so plainly rather than dying with a confusing "no such file" —
# a stale runbook step that errors obscurely is worse than one that explains
# itself. `verify` does not touch the source root and stays useful indefinitely as
# a check that the ECS code still matches what is deployed.
require_source_state() {
  # Gate on the root's code, not the directory: `git rm` leaves untracked
  # .terraform provider cache behind, so a bare -d test stays true against a
  # gutted root and the guard never fires.
  [[ -f "$CFG_DIR/main.tf" ]] && return 0
  echo "The sparc/config root no longer exists — this migration is COMPLETE."
  echo "AWS Config now lives in the ECS state (AWS/ECS/modules/aws_config)."
  echo "Only 'verify' still applies; it re-checks the ECS code against live AWS."
  exit 0
}

init() {
  local dir="$1"
  ( cd "$dir" && terraform init -input=false -no-color -backend-config=backend.hcl >/dev/null )
}

# Config rules are a for_each map, so their keys are discovered rather than listed.
rule_addresses() {
  ( cd "$CFG_DIR" && terraform state list 2>/dev/null | grep '^aws_config_config_rule\.managed\[' )
}

cmd_plan() {
  require_source_state
  init "$CFG_DIR"
  echo "Resources that will move from sparc/config -> sparc/ecs:"
  for m in "${MOVES[@]}"; do printf '  %-58s -> %s\n' "${m%%|*}" "${m##*|}"; done
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    printf '  %-58s -> %s\n' "$r" "module.aws_config.$r"
  done < <(rule_addresses)
  echo
  echo "Total: $(( ${#MOVES[@]} + $(rule_addresses | wc -l | tr -d ' ') )) instances"
  echo "Nothing has been changed. Run 'import' next."
}

cmd_import() {
  require_source_state
  init "$CFG_DIR"; init "$ECS_DIR"
  echo "Importing into sparc/ecs (source state untouched)..."
  for m in "${MOVES[@]}"; do
    src="${m%%|*}"; dst="${m##*|}"
    id=$( cd "$CFG_DIR" && terraform state show -no-color "$src" 2>/dev/null | awk -F'"' '/^[[:space:]]+id[[:space:]]+=/{print $2; exit}' )
    if [[ -z "$id" ]]; then echo "  SKIP  $src (not in source state)"; continue; fi
    if ( cd "$ECS_DIR" && terraform state show "$dst" >/dev/null 2>&1 ); then
      echo "  have  $dst"; continue
    fi
    echo "  import $dst  <- id=$id"
    ( cd "$ECS_DIR" && terraform import -no-color \
        -var-file=envs/prod/terraform.tfvars -var="enable_aws_config=true" "$dst" "$id" >/dev/null )
  done
  while IFS= read -r src; do
    [[ -z "$src" ]] && continue
    dst="module.aws_config.$src"
    id=$( cd "$CFG_DIR" && terraform state show -no-color "$src" 2>/dev/null | awk -F'"' '/^[[:space:]]+name[[:space:]]+=/{print $2; exit}' )
    [[ -z "$id" ]] && { echo "  SKIP  $src (no name)"; continue; }
    if ( cd "$ECS_DIR" && terraform state show "$dst" >/dev/null 2>&1 ); then echo "  have  $dst"; continue; fi
    echo "  import $dst  <- $id"
    ( cd "$ECS_DIR" && terraform import -no-color \
        -var-file=envs/prod/terraform.tfvars -var="enable_aws_config=true" "$dst" "$id" >/dev/null )
  done < <(rule_addresses)
  rm -f "$MARKER"
  echo "Import complete. Run 'verify' before releasing the old state."
}

# The AWS Config API does not return a conformance pack's template body
# (DescribeConformancePacks reports delivery settings only), so `terraform
# import` records template_body as null and the first plan always wants to write
# it. That is the ONE diff this migration legitimately cannot import away.
#
# Accepting it on trust would be the same mistake as the grep this function
# replaced, so it is accepted only after proving the deployed pack is equivalent
# to the template: same managed rules, same SourceIdentifier set, none extra and
# none missing. If that check fails the template genuinely differs from what is
# deployed, and writing it would change live rule evaluations.
pack_is_equivalent() {
  local pack_name="$1"
  python3 - "$pack_name" <<'PY'
import json, re, subprocess, sys

pack = sys.argv[1]
tmpl = "AWS/ECS/modules/aws_config/sparc-ecs-nist-800-53-rev5-conformance-pack.yaml"

body = open(tmpl).read().split("Resources:", 1)[1]
want = set()
for block in re.split(r"^  (?=[A-Za-z0-9]+:\s*$)", body, flags=re.M):
    if "AWS::Config::ConfigRule" not in block:
        continue
    m = re.search(r"SourceIdentifier:\s*([A-Z0-9_]+)", block)
    if m:
        want.add(m.group(1))

arn = subprocess.run(
    ["aws", "configservice", "describe-conformance-packs",
     "--conformance-pack-names", pack,
     "--query", "ConformancePackDetails[0].ConformancePackArn", "--output", "text"],
    capture_output=True, text=True).stdout.strip()
suffix = arn.rsplit("/", 1)[-1] if "/" in arn else ""
if not suffix:
    print("    could not resolve the conformance pack ARN", file=sys.stderr)
    sys.exit(1)

rules = json.loads(subprocess.run(
    ["aws", "configservice", "describe-config-rules", "--output", "json"],
    capture_output=True, text=True).stdout)["ConfigRules"]
have = {r["Source"]["SourceIdentifier"] for r in rules if suffix in r["ConfigRuleName"]}

if want and want == have:
    print(f"    deployed pack matches template: {len(want)} managed rules, identical identifiers")
    sys.exit(0)
print(f"    template-only: {sorted(want - have)}", file=sys.stderr)
print(f"    deployed-only: {sorted(have - want)}", file=sys.stderr)
sys.exit(1)
PY
}

cmd_verify() {
  init "$ECS_DIR"
  echo "Asserting the ECS plan is clean for the imported resources..."
  # The plan JSON is the only trustworthy signal here. Grepping the human-readable
  # plan for "will be created" misses IN-PLACE UPDATES entirely, and an in-place
  # update is exactly what this step exists to catch — a delivery channel whose
  # bucket or frequency differs from what is deployed reads as clean and then
  # silently rewrites live configuration on the next apply.
  #
  # IAM is targeted per-resource rather than as a whole module: module.iam also
  # holds the 17 evidence-emit roles and the rest of the boundary's identities,
  # and an unrelated pending change there would fail this check for the wrong
  # reason.
  set +e
  ( cd "$ECS_DIR" && terraform plan -no-color -lock=false -out="$PLAN_BIN" \
      -var-file=envs/prod/terraform.tfvars -var="enable_aws_config=true" \
      -target=module.aws_config \
      -target=module.iam.aws_iam_role.aws_config \
      -target=module.iam.aws_iam_role_policy.aws_config_s3 \
      -target=module.iam.aws_iam_role_policy_attachment.aws_config_managed \
      >"$PLAN_LOG" 2>&1 )
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "FAIL — terraform plan errored (exit $rc)."
    tail -30 "$PLAN_LOG"
    exit 1
  fi

  # Classify every proposed change from the plan JSON. Anything that is not the
  # known conformance-pack template_body artifact fails the migration.
  set +e
  ( cd "$ECS_DIR" && terraform show -json "$PLAN_BIN" ) >"$PLAN_JSON" 2>>"$PLAN_LOG"
  verdict=$( python3 - "$PLAN_JSON" <<'PY'
import json, sys

plan = json.load(open(sys.argv[1]))
ARTIFACT = "module.aws_config.aws_config_conformance_pack.nist[0]"
seen = False

for rc in plan.get("resource_changes", []):
    actions = rc["change"]["actions"]
    if actions == ["no-op"]:
        continue
    addr = rc["address"]
    before = rc["change"].get("before") or {}
    after = rc["change"].get("after") or {}
    changed = {k for k in set(before) | set(after) if before.get(k) != after.get(k)}
    if (addr == ARTIFACT and actions == ["update"]
            and changed == {"template_body"} and not before.get("template_body")):
        seen = True
        continue
    print(f"UNEXPECTED {addr} {actions} {sorted(changed)}")
    sys.exit(1)

print("ARTIFACT" if seen else "CLEAN")
PY
)
  prc=$?
  set -e
  rm -f "$PLAN_BIN"

  if [[ "$prc" -ne 0 ]]; then
    echo "FAIL — the plan proposes changes beyond the known import artifact:"
    echo "$verdict" | sed 's/^/       /'
    echo "       Do NOT release the old state. Reconcile the code, then re-verify."
    echo "       Full plan: $PLAN_LOG"
    exit 1
  fi

  if [[ "$verdict" == "ARTIFACT" ]]; then
    echo "NOTE — the only pending change is the conformance pack's template_body,"
    echo "       which import cannot populate (the API does not return it)."
    echo "       Proving the deployed pack is equivalent to the template..."
    if ! pack_is_equivalent "example-nist-800-53-rev5"; then
      echo "FAIL — the deployed pack does NOT match the template. Writing it would"
      echo "       change live rule evaluations. Do NOT release the old state."
      exit 1
    fi
    echo "       Equivalence proven; the first apply re-asserts the same template."
  fi

  echo "PASS — no unexplained changes for the migrated resources."
  touch "$MARKER"
  echo "Safe to run 'release'."
}

cmd_release() {
  require_source_state
  [[ -f "$MARKER" ]] || { echo "Refusing: run 'verify' first — releasing before verifying risks orphaning live resources."; exit 1; }
  init "$CFG_DIR"
  echo "Removing from sparc/config (resources stay live; only the state entry goes)..."
  for m in "${MOVES[@]}"; do
    src="${m%%|*}"
    ( cd "$CFG_DIR" && terraform state rm -no-color "$src" >/dev/null 2>&1 ) && echo "  rm  $src" || echo "  --  $src (already gone)"
  done
  while IFS= read -r src; do
    [[ -z "$src" ]] && continue
    ( cd "$CFG_DIR" && terraform state rm -no-color "$src" >/dev/null 2>&1 ) && echo "  rm  $src" || echo "  --  $src"
  done < <(rule_addresses)
  echo
  echo "sparc/config now holds: $( cd "$CFG_DIR" && terraform state list | wc -l | tr -d ' ' ) entries"
  echo "The AWS/config code and its pipeline jobs can now be deleted safely."
}

case "${1:-}" in
  plan) cmd_plan ;;
  import) cmd_import ;;
  verify) cmd_verify ;;
  release) cmd_release ;;
  *) sed -n '/^# USAGE/,/^# ===/p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
