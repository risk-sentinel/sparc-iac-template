#!/usr/bin/env python3
"""
Parse the AWS FedRAMP CRM Excel workbook into machine-readable JSON.

Source: AWS Artifact → FedRAMP Customer Package → SSP Appendix J
The Excel file is NDA-protected and gitignored.

Usage:
    python3 oscal/scripts/parse_aws_crm.py \
        --input docs/FedRAMP_20x/aws-artifact/AWS_SSP-Appendix-J_CIS-and-CRM-Workbook_v26.01.U-FINAL.xlsx \
        --output docs/FedRAMP_20x/aws-artifact/aws-crm-parsed.json
"""

import argparse
import json

import openpyxl


def parse_crm_sheet(wb):
    """Parse the Combined CRM sheet into a dict of control entries."""
    ws = wb["Combined CRM - FedRAMP and DoD"]
    crm = {}
    for row in ws.iter_rows(min_row=4, values_only=True):
        cid = str(row[0]).strip() if row[0] else ""
        if not cid or cid == "None":
            continue
        crm[cid] = {
            "fedramp_baseline": str(row[1]).strip() if row[1] else "",
            "dod_baseline": str(row[2]).strip() if row[2] else "",
            "can_inherit": str(row[3]).strip() if row[3] else "",
            "customer_responsibility": str(row[4]).strip() if row[4] else "",
        }
    return crm


def parse_cis_sheet(wb):  # NOSONAR S3776 (#526): inherent complexity in tested tooling; refactoring solely for the metric risks behavior change without benefit
    """Parse the Combined CIS sheet into a dict of implementation status."""
    ws = wb["Combined CIS - FedRAMP and DoD"]
    cis = {}
    for row in ws.iter_rows(min_row=4, values_only=True):
        cid = str(row[0]).strip() if row[0] else ""
        if not cid or cid == "None":
            continue
        cis[cid] = {
            "fedramp_baseline": str(row[1]).strip() if row[1] else "",
            "implemented": bool(row[3]) if row[3] else False,
            "partially_implemented": bool(row[4]) if row[4] else False,
            "planned": bool(row[5]) if row[5] else False,
            "alternative": bool(row[6]) if row[6] else False,
            "na": bool(row[7]) if row[7] else False,
            "sp_corporate": bool(row[8]) if row[8] else False,
            "sp_system_specific": bool(row[9]) if row[9] else False,
            "sp_hybrid": bool(row[10]) if row[10] else False,
            "customer_configured": bool(row[11]) if row[11] else False,
            "customer_provided": bool(row[12]) if row[12] else False,
            "shared": bool(row[13]) if row[13] else False,
            "inherited": bool(row[14]) if row[14] else False,
        }
    return cis


def main():
    parser = argparse.ArgumentParser(
        description="Parse AWS FedRAMP CRM workbook into JSON"
    )
    parser.add_argument("--input", required=True, help="Path to CRM Excel file")
    parser.add_argument("--output", required=True, help="Path to write parsed JSON")
    parser.add_argument("--baseline", default="HIGH",
                        choices=["HIGH", "MODERATE", "LOW", "ALL"],
                        help="Filter to FedRAMP baseline (default: HIGH)")
    args = parser.parse_args()

    print(f"Loading workbook: {args.input}")
    wb = openpyxl.load_workbook(args.input, read_only=True)

    crm = parse_crm_sheet(wb)
    print(f"  CRM entries: {len(crm)}")

    cis = parse_cis_sheet(wb)
    print(f"  CIS entries: {len(cis)}")

    # Merge CRM and CIS
    combined = {}
    for cid in sorted(set(list(crm.keys()) + list(cis.keys()))):
        entry = {"control_id": cid}
        if cid in cis:
            entry.update(cis[cid])
        if cid in crm:
            entry["can_inherit"] = crm[cid]["can_inherit"]
            entry["customer_responsibility"] = crm[cid]["customer_responsibility"]
        combined[cid] = entry

    # Filter by baseline
    if args.baseline != "ALL":
        combined = {
            k: v for k, v in combined.items()
            if args.baseline.upper() in v.get("fedramp_baseline", "").upper()
            or "MODERATE" in v.get("fedramp_baseline", "").upper()
        }

    # Summary
    inherit_yes = [c for c in combined.values() if c.get("can_inherit") == "Yes"]
    inherit_partial = [c for c in combined.values() if c.get("can_inherit") == "Partial"]
    inherit_no = [c for c in combined.values() if c.get("can_inherit") == "No"]

    print(f"\nFiltered to {args.baseline} baseline: {len(combined)} entries")
    print(f"  Fully inheritable: {len(inherit_yes)}")
    print(f"  Partially inheritable: {len(inherit_partial)}")
    print(f"  Customer only: {len(inherit_no)}")

    with open(args.output, "w") as f:
        json.dump(combined, f, indent=2, default=str)
    print(f"\nWritten to {args.output}")


if __name__ == "__main__":
    main()
