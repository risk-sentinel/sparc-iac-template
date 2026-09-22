# CDEF → NIST 800-53 enrichment (repeatable, revision-parameterized)

Turns AWS's own control layer into **published, reusable OSCAL 1.2 mapping-collections**
that map AWS controls → NIST SP 800-53 — at **whichever revision a user needs
(Rev 4 or Rev 5)**. This is the process we run ahead of the curve so our curated
CDEFs load straight into SPARC as published components (#287, #593).

## Why this exists

AWS Labs' published CDEFs key controls to **AWS Security Hub** ids (`S3.1`), not
NIST — the NIST bridge lives in **MITRE's `hdf-libs` mapping tables** (AWS Config
rule → NIST 800-53), which are Rev 4. Real systems need Rev 4 *or* Rev 5 depending
on the authorization, so the pipeline is parameterized by target revision and the
Rev 4→Rev 5 translation is driven by NIST's own crosswalk. Everything is vendored
with provenance and deterministic, so anyone can reproduce or share the output.

## Data (vendored — see `oscal/mappings/PROVENANCE.md`)

| File | What | Source (pinned) |
|---|---|---|
| `oscal/mappings/awsconfig-nist-mappings.json` | AWS Config rule → NIST 800-53 **Rev 4** | MITRE `hdf-libs` |
| `oscal/mappings/nist_r4_to_r5.json` | NIST **Rev 4 → Rev 5** crosswalk (withdrawn/incorporated redirects; identity otherwise) | NIST official comparison workbook |
| `AWS/CDEF/aws-labs/*.oscal.json` | AWS Labs CDEFs (Security Hub inventory), OSCAL 1.2.1 | `awslabs/oscal-content-for-aws-services` |

## Scripts

- **`extract_nist_r4_to_r5.py`** — parse the NIST comparison workbook (`.xlsx`) →
  `nist_r4_to_r5.json`. Re-run whenever NIST republishes; the source URL is pinned
  in `PROVENANCE.md`.
- **`build_cdef_mapping.py`** — emit the OSCAL 1.2 `mapping-collection`
  (AWS Config rules → NIST 800-53). Deterministic (uuid5 + explicit
  `--last-modified`), so re-runs are byte-identical.
- **`state_cdef_coverage.py`** — the state-driven boundary analyzer (which AWS
  services we deploy / adopt / need custom).

## Run it

Choose the revision and the scope:

```bash
# Rev 5, scoped to the AWS Config rules we actually DEPLOY (state-grounded)
python3 oscal/scripts/build_cdef_mapping.py \
  --state s3://<tf-state-bucket>/sparc/config/terraform.tfstate \
  --target-rev 5 --last-modified 2026-07-27T00:00:00Z \
  --output oscal/mappings/aws-config-to-nist80053r5.mapping.json

# Rev 4, generic (every rule in the mapping table — shareable reference)
python3 oscal/scripts/build_cdef_mapping.py \
  --all-rules --target-rev 4 --last-modified 2026-07-27T00:00:00Z \
  --output oscal/mappings/aws-config-to-nist80053r4.mapping.json
```

`--target-rev {4,5}` is the "which regulation?" switch. Rev 4 is emitted as
published by MITRE; Rev 5 translates every NIST id through `nist_r4_to_r5.json`
(identity for the ~161/164 that carry over, redirect for the withdrawn few).

## Output

A self-contained OSCAL 1.2.1 `mapping-collection` (`mappings[] →
{source-resource, target-resource, maps[{relationship, sources, targets}]}` +
required `provenance`), structurally matching SPARC's `OscalMappingExportService`.
Load it into SPARC as a published, reusable mapping. Authoritative schema
validation happens SPARC-side (its JS validator supports the OSCAL `\p{L}` token
patterns Python's `re` cannot).

## Regenerate the crosswalk from a new NIST workbook

```bash
curl -sSL -o /tmp/r4r5.xlsx "<pinned NIST workbook URL from PROVENANCE.md>"
python3 oscal/scripts/extract_nist_r4_to_r5.py \
  --workbook /tmp/r4r5.xlsx --output oscal/mappings/nist_r4_to_r5.json \
  --source-url "<url>" --retrieved "$(date -u +%Y-%m-%d)"
```
