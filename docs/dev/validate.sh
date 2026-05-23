#!/bin/bash
set -euo pipefail

# ===========================================================================
# sparc-iac Validation Script
# ===========================================================================
# Run from repo root: bash docs/dev/validate.sh [pattern]
#
# Usage:
#   bash docs/dev/validate.sh          # Validate all patterns
#   bash docs/dev/validate.sh ecs      # Validate ECS only
#   bash docs/dev/validate.sh ec2      # Validate EC2 only
#   bash docs/dev/validate.sh azure    # Validate Azure VM only
#   bash docs/dev/validate.sh oscal    # Validate OSCAL documents only
#   bash docs/dev/validate.sh checkov  # Run checkov on all patterns
# ===========================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; WARN=$((WARN + 1)); }
header() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

# ---------------------------------------------------------------------------
# Terraform Validation
# ---------------------------------------------------------------------------
validate_terraform() {
    local dir=$1
    local name=$2

    header "Terraform: $name ($dir)"

    if [ ! -d "$dir" ]; then
        fail "$dir does not exist"
        return
    fi

    # Init
    if (cd "$dir" && terraform init -backend=false > /dev/null 2>&1); then
        pass "terraform init"
    else
        fail "terraform init"
        return
    fi

    # Validate
    if (cd "$dir" && terraform validate > /dev/null 2>&1); then
        pass "terraform validate"
    else
        fail "terraform validate"
    fi

    # Format check
    if (cd "$dir" && terraform fmt -check -recursive > /dev/null 2>&1); then
        pass "terraform fmt"
    else
        fail "terraform fmt (run: terraform fmt -recursive $dir)"
    fi
}

# ---------------------------------------------------------------------------
# OSCAL JSON Validation
# ---------------------------------------------------------------------------
validate_oscal() {
    header "OSCAL Documents"

    local total=0
    local valid=0

    for f in $(find AWS/CDEF Azure/CDEF oscal -name "*.json" 2>/dev/null | sort); do
        total=$((total + 1))
        if python3 -m json.tool "$f" > /dev/null 2>&1; then
            valid=$((valid + 1))
        else
            fail "Invalid JSON: $f"
        fi
    done

    if [ "$valid" -eq "$total" ]; then
        pass "All $total OSCAL JSON files valid"
    else
        fail "$((total - valid)) of $total files invalid"
    fi
}

# ---------------------------------------------------------------------------
# CDEF Coverage
# ---------------------------------------------------------------------------
validate_cdefs() {
    header "CDEF Inventory"

    for dir in AWS/CDEF/ECS AWS/CDEF/EC2 Azure/CDEF/VM; do
        if [ -d "$dir" ]; then
            count=$(find "$dir" -name "*.json" | wc -l | tr -d ' ')
            pass "$dir: $count CDEFs"
        else
            warn "$dir not found"
        fi
    done
}

# ---------------------------------------------------------------------------
# SSP Assembly Test
# ---------------------------------------------------------------------------
validate_ssp_assembly() {
    header "SSP Assembly"

    local profile="docs/FedRAMP_20x/NIST_SP-800-53_rev5_HIGH-baseline-resolved-profile_catalog.json"

    if [ ! -f "$profile" ]; then
        fail "HIGH baseline profile not found"
        return
    fi

    for pattern in ecs ec2 azure-vm; do
        case $pattern in
            ecs)      cdef_dir="AWS/CDEF/ECS"; name="SPARC ECS Fargate" ;;
            ec2)      cdef_dir="AWS/CDEF/EC2"; name="SPARC EC2" ;;
            azure-vm) cdef_dir="Azure/CDEF/VM"; name="SPARC Azure VM" ;;
        esac

        if [ ! -d "$cdef_dir" ]; then
            warn "Skipping $pattern — $cdef_dir not found"
            continue
        fi

        output="/tmp/validate-ssp-${pattern}.json"
        if python3 oscal/scripts/assemble_ssp.py \
            --cdef-dir "$cdef_dir" \
            --profile "$profile" \
            --system-name "$name" \
            --output "$output" > /dev/null 2>&1; then
            controls=$(python3 -c "
import json
d=json.load(open('$output'))
reqs=d['system-security-plan']['control-implementation']['implemented-requirements']
print(len(reqs))" 2>/dev/null)
            pass "$pattern SSP: $controls controls"
        else
            fail "$pattern SSP assembly failed"
        fi
        rm -f "$output" "/tmp/validate-ssp-${pattern}-gaps.md"
    done
}

# ---------------------------------------------------------------------------
# Checkov Scan
# ---------------------------------------------------------------------------
run_checkov() {
    local dir=$1
    local name=$2
    local type=$3

    header "Checkov: $name ($dir)"

    if ! command -v checkov &> /dev/null; then
        warn "checkov not installed — skipping"
        return
    fi

    mkdir -p checkov-results
    local epoch
    epoch=$(date +%s)

    local result
    result=$(checkov -d "$dir" --framework terraform \
        --output json --output sarif \
        --output-file-path checkov-results/ \
        --compact --quiet 2>&1 | grep -E '"(passed|failed)"' || true)

    if [ -f checkov-results/results_json.json ]; then
        mv checkov-results/results_json.json \
            "checkov-results/${type}_${epoch}_results.json"
        mv checkov-results/results_sarif.sarif \
            "checkov-results/${type}_${epoch}_results.sarif"

        local passed failed
        passed=$(python3 -c "
import json
d=json.load(open('checkov-results/${type}_${epoch}_results.json'))
print(d.get('summary',{}).get('passed',0))" 2>/dev/null || echo "?")
        failed=$(python3 -c "
import json
d=json.load(open('checkov-results/${type}_${epoch}_results.json'))
print(d.get('summary',{}).get('failed',0))" 2>/dev/null || echo "?")

        pass "Checkov $type: $passed passed, $failed failed (epoch: $epoch)"
    else
        fail "Checkov $type produced no results"
    fi
}

# ---------------------------------------------------------------------------
# Workflow YAML Validation
# ---------------------------------------------------------------------------
validate_workflows() {
    header "GitHub Workflows"

    for f in .github/workflows/*.yml; do
        if [ -f "$f" ]; then
            # Basic structure check
            if grep -q "^name:" "$f" && grep -q "^on:" "$f"; then
                pass "$(basename "$f"): valid structure"
            else
                fail "$(basename "$f"): missing name or on trigger"
            fi
        fi
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
TARGET="${1:-all}"

echo "sparc-iac validation — $(date)"
echo "Target: $TARGET"

case "$TARGET" in
    ecs)
        validate_terraform "AWS/ECS" "ECS Fargate"
        ;;
    ec2)
        validate_terraform "AWS/EC2" "EC2"
        ;;
    azure)
        validate_terraform "Azure/VM" "Azure VM"
        ;;
    oscal)
        validate_oscal
        validate_cdefs
        validate_ssp_assembly
        ;;
    checkov)
        run_checkov "AWS/ECS" "ECS Fargate" "ecs"
        run_checkov "AWS/EC2" "EC2" "ec2"
        run_checkov "Azure/VM" "Azure VM" "azure-vm"
        ;;
    all)
        validate_terraform "AWS/ECS" "ECS Fargate"
        validate_terraform "AWS/EC2" "EC2"
        validate_terraform "Azure/VM" "Azure VM"
        validate_oscal
        validate_cdefs
        validate_ssp_assembly
        validate_workflows
        ;;
    *)
        echo "Usage: bash docs/dev/validate.sh [ecs|ec2|azure|oscal|checkov|all]"
        exit 1
        ;;
esac

# Summary
echo ""
echo "=============================="
echo -e "  ${GREEN}PASS: $PASS${NC}"
if [ "$FAIL" -gt 0 ]; then
    echo -e "  ${RED}FAIL: $FAIL${NC}"
fi
if [ "$WARN" -gt 0 ]; then
    echo -e "  ${YELLOW}WARN: $WARN${NC}"
fi
echo "=============================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
