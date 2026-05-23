# SPARC CI Runner Container

Pre-built container with all CI/CD tools for GitHub Actions pipelines.
Eliminates per-run tool installs and ensures deterministic builds.

## Tools Included

| Tool | Version | Purpose |
|------|---------|---------|
| Python | 3.12 | Script execution, Checkov, Semgrep |
| Terraform | 1.5.7 | Infrastructure as Code |
| Node.js | 22 | SAF CLI runtime |
| Checkov | 3.2.506 | IaC security scanning |
| Semgrep | 1.157.0 | SAST scanning |
| pip-audit | 2.10.0 | Python dependency audit |
| SAF CLI | 1.5.3 | HDF conversion (MITRE) |
| TruffleHog | 3.88.1 | Secret detection (binary) |
| AWS CLI | v2 | AWS operations |
| GitHub CLI | 2.74.1 | GitHub API |
| cosign | latest | Image signature verification |
| matplotlib | 3.10.8 | Pipeline performance charts |

## Build

```bash
# Local build
docker build -t sparc-ci-runner -f .github/runner/Dockerfile .github/runner/

# Test
docker run --rm sparc-ci-runner terraform version
docker run --rm sparc-ci-runner checkov --version
docker run --rm sparc-ci-runner saf --version
```

## CI Build

The `build-runner.yml` workflow builds, scans, signs, and pushes to ECR:
- **Weekly** (Monday 6am UTC) — picks up tool patches
- **On Dockerfile change** — immediate rebuild
- **Manual dispatch** — emergency rebuild

## Image Tags

- `latest` — most recent build
- `YYYY.MM.DD` — date-stamped for pinning

## Security

- **Trivy scan** — fails build on CRITICAL CVEs
- **cosign signature** — keyless OIDC signing via Fulcio/Rekor
- **Docker Hub** — `risksentinel/sparc-ci-runner` (separate from ECR app images)
- **CVE tracking** — `container-baseline.yml` (same disposition workflow as Checkov)

## Updating Tool Versions

1. Edit version ENVs in `.github/runner/Dockerfile`
2. Push — `build-runner.yml` triggers automatically
3. All CI workflows pick up the new image on next run

## Backout

If the container breaks CI:
1. Remove `container:` from the failing workflow job
2. Uncomment the setup/install steps (kept as comments)
3. Push — workflows fall back to per-run installs
