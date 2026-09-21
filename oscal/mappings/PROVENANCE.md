# Mapping data provenance

Vendored external mapping data used to enrich published AWS CDEFs with NIST
800-53 coverage. Re-fetch/re-extract with the commands below; keep this file in
sync when bumping any pin.

## `awsconfig-nist-mappings.json` — AWS Config rule → NIST 800-53 (Rev 4)
- **Source:** MITRE `hdf-libs` `hdf-mappings/src/data/awsconfig-mappings.json`
- **Pinned commit:** `67048f752ec66431c7861add967c759423c760d5`
- **Retrieved:** 2026-07-27
- **Revision:** NIST 800-53 **Rev 4** (translated to Rev 5 via the crosswalk below)
- Re-fetch:
  ```
  gh api repos/mitre/hdf-libs/contents/hdf-mappings/src/data/awsconfig-mappings.json?ref=<sha> \
    --jq '.content' | base64 -d > oscal/mappings/awsconfig-nist-mappings.json
  ```

## `nist_r4_to_r5.json` — NIST 800-53 Rev 4 → Rev 5 crosswalk
- **Source:** NIST official `sp800-53r4-to-r5-comparison-workbook.xlsx`, sheet
  "Rev4 Rev5 Compared"
- **URL:** https://csrc.nist.gov/files/pubs/sp/800/53/r5/upd1/final/docs/sp800-53r4-to-r5-comparison-workbook.xlsx
- **Retrieved:** 2026-07-27
- **Extracted by:** `oscal/scripts/extract_nist_r4_to_r5.py` (re-runnable)
- Only the ~53 withdrawn/incorporated redirects are recorded; every other control
  carries over to Rev 5 with an identical id (identity default).

## `AWS/CDEF/aws-labs/` — AWS Labs published CDEFs (Security Hub inventory)
- **Source:** `awslabs/oscal-content-for-aws-services` `component-definitions/`
- **Pinned commit:** `4a1779ffb556c4ab8fb3dad94a19d4d198116803` (see `AWS/CDEF/aws-labs/pinned-commit.txt`)
- **OSCAL version:** 1.2.1

## Generated artifacts (not vendored — reproducible)
- `aws-config-to-nist80053r{4,5}.mapping.json` — OSCAL 1.2 mapping-collections,
  produced by `oscal/scripts/build_cdef_mapping.py` (deterministic; see
  `docs/dev/cdef_nist_enrichment.md`).
