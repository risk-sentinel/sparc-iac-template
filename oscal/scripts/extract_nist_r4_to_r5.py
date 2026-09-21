#!/usr/bin/env python3
"""Extract the NIST SP 800-53 rev4 -> rev5 control crosswalk from NIST's official
comparison workbook into a machine-readable JSON.

This makes the crosswalk **repeatable**: re-run it whenever NIST republishes the
workbook (the source URL is pinned in oscal/mappings/PROVENANCE.md). The output
feeds build_cdef_mapping.py's ``--target-rev 5`` translation.

Source: NIST `sp800-53r4-to-r5-comparison-workbook.xlsx`, sheet
"Rev4 Rev5 Compared". Every control that is NOT flagged Withdrawn carries over to
rev5 with an identical ID (identity mapping — the common case); the ~300
Withdrawn rows redirect a rev4 control to the rev5 control it was "Incorporated
into". The emitted JSON records only the redirects + status metadata; callers
default to identity for anything absent.

Usage:
  extract_nist_r4_to_r5.py --workbook sp800-53r4-to-r5-comparison-workbook.xlsx \
    --output oscal/mappings/nist_r4_to_r5.json --source-url <pinned NIST url>
"""
from __future__ import annotations

import argparse
import json
import re

import openpyxl

# "Incorporated into AC-2k", "Incorporated into AC-16 and AC-4", etc. Capture the
# NIST control tokens (AC-2, AC-16, AC-2(3)); trailing lowercase = statement part.
_INCORP = re.compile(r"[Ii]ncorporated into\s+(.+)")
_CTRL = re.compile(r"\b([A-Z]{2}-\d+(?:\(\d+\))?)")
# The workbook's zero-padded dash-enhancement detail refs (e.g. "AU-03-2",
# "AC-02-1") bleed in from adjacent columns; strip them before matching controls.
_DETAIL_REF = re.compile(r"\b[A-Z]{2}-\d+(?:\(\d+\))?-\d+\b")


def _norm(cid: str) -> str:
    """Canonical NIST id: strip zero-padding. AC-02 -> AC-2, AC-2(01) -> AC-2(1)."""
    m = re.match(r"([A-Z]{2})-0*(\d+)(?:\(0*(\d+)\))?", cid)
    if not m:
        return cid
    out = f"{m.group(1)}-{m.group(2)}"
    if m.group(3):
        out += f"({m.group(3)})"
    return out


def _incorporated_targets(text: str, source_id: str) -> list[str]:
    """Targets of an 'Incorporated into ...' notation, normalized, self-ref removed.

    A bounded window after the phrase avoids bleed from adjacent workbook columns;
    the source control's own base id (which recurs zero-padded in detail columns)
    is dropped so only genuine redirect targets remain.
    """
    m = _INCORP.search(text)
    if not m:
        return []
    window = _DETAIL_REF.sub(" ", m.group(1)[:50])
    source_base = _norm(source_id)
    targets = {_norm(t) for t in _CTRL.findall(window)}
    targets.discard(source_base)
    return sorted(targets)


def extract(workbook_path: str) -> dict:
    wb = openpyxl.load_workbook(workbook_path, read_only=True, data_only=True)
    ws = wb["Rev4 Rev5 Compared"]
    rows = list(ws.iter_rows(values_only=True))
    hdr_i = next(i for i, r in enumerate(rows) if r and r[0] == "ID")

    withdrawn: dict[str, list[str]] = {}
    withdrawn_no_target: list[str] = []
    all_ids: list[str] = []
    for r in rows[hdr_i + 1:]:
        if not r or not r[0]:
            continue
        cid = str(r[0]).strip()
        all_ids.append(cid)
        notation = " ".join(str(c) for c in r[1:] if c)
        low = notation.lower()
        # Only genuine rev5 withdrawals redirect; "previously withdrawn in Rev4"
        # controls were already absent in rev4 baselines — skip them.
        if "previously withdrawn in rev4" in low:
            continue
        if re.search(r"\bwithdrawn\b", low):
            targets = _incorporated_targets(notation, cid)
            if targets:
                withdrawn[cid] = targets
            else:
                withdrawn_no_target.append(cid)
    return {
        "withdrawn_incorporated": withdrawn,   # rev4 id -> [rev5 target ids]
        "withdrawn_no_target": sorted(withdrawn_no_target),
        "rev5_control_count": len(all_ids),
        "_note": "Absent ids map to themselves (identity). Only rev5 withdrawals "
                 "that were incorporated into another control are redirected.",
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Extract NIST rev4->rev5 crosswalk")
    ap.add_argument("--workbook", required=True,
                    help="NIST sp800-53r4-to-r5-comparison-workbook.xlsx")
    ap.add_argument("--output", required=True)
    ap.add_argument("--source-url", default="",
                    help="pinned NIST workbook URL (recorded in output provenance)")
    ap.add_argument("--retrieved", default="",
                    help="ISO date the workbook was retrieved (provenance)")
    args = ap.parse_args()

    data = extract(args.workbook)
    data["provenance"] = {"source_url": args.source_url, "retrieved": args.retrieved,
                          "source": "NIST SP 800-53 rev4->rev5 comparison workbook"}
    with open(args.output, "w") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.write("\n")
    print(f"wrote {args.output}: {len(data['withdrawn_incorporated'])} redirects, "
          f"{len(data['withdrawn_no_target'])} withdrawn-no-target, "
          f"{data['rev5_control_count']} rev5 controls scanned")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
